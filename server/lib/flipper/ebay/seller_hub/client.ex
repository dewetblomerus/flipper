defmodule Flipper.Ebay.SellerHub.Client do
  @moduledoc """
  Reads and writes a Seller Hub draft through its listing page, with the browser cookie.
  """

  alias Flipper.Ebay.SellerHub.OptionalFields
  alias Flipper.Ebay.Session

  @image_types ~w(image/jpeg image/png image/gif image/webp image/avif image/heic)
  @drafts_url "https://www.ebay.com/sh/lst/drafts"
  # Where each of the page's data modules starts. TextualDisplay objects are labels.
  @module_key ~r/"([A-Z][A-Z0-9_]+)":(?=\{"_type":"(?!TextualDisplay")[A-Za-z0-9]+")/
  @secret_keys ~w(epsData srt csrfToken)
  @user_agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36"
  @browser_headers [
    {"accept",
     "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"},
    {"accept-language", "en-US,en;q=0.9"},
    {"cache-control", "max-age=0"},
    {"referer", @drafts_url},
    {"sec-ch-ua", ~s("Not-A.Brand";v="99", "Google Chrome";v="157", "Chromium";v="157")},
    {"sec-ch-ua-mobile", "?0"},
    {"sec-ch-ua-platform", ~s("Linux")},
    {"sec-fetch-dest", "document"},
    {"sec-fetch-mode", "navigate"},
    {"sec-fetch-site", "same-origin"},
    {"sec-fetch-user", "?1"},
    {"upgrade-insecure-requests", "1"},
    {"user-agent", @user_agent}
  ]

  def fetch(ebay_draft_id, opts \\ []) when is_binary(ebay_draft_id) do
    case cookie_from(opts) do
      cookie when is_binary(cookie) and cookie != "" ->
        request(ebay_draft_id, cookie, Keyword.delete(opts, :cookie))

      _ ->
        {:error, "eBay cookie is not set"}
    end
  end

  defp cookie_from(opts) do
    if Keyword.has_key?(opts, :cookie) do
      opts[:cookie]
    else
      Session.cookie()
    end
  end

  def download(url) when is_binary(url) do
    case Req.get(url, decode_body: false, redirect: true) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        type = media_type(headers)

        if type in @image_types and is_binary(body) and body != "" do
          {:ok, body, type}
        else
          {:error, "photo is not an image"}
        end

      {:ok, %{status: status}} ->
        {:error, "photo returned #{status}"}

      {:error, _reason} ->
        {:error, "photo download failed"}
    end
  end

  def parse(body) when is_binary(body) do
    values = json_values(body)

    urls =
      values
      |> Enum.flat_map(&image_urls/1)
      |> Enum.map(&normalize_url/1)
      |> Enum.uniq()

    title =
      values
      |> Enum.flat_map(&titles/1)
      |> choose_title()
      |> case do
        {title, _count} -> title
        nil -> nil
      end

    if is_nil(title) and urls == [] do
      {:error, "eBay draft had no title or photos"}
    else
      {:ok, %{title: title, photo_urls: urls}}
    end
  end

  def upload_photo(ebay_draft_id, path, content_type, opts \\ []) do
    with {:ok, cookie} <- signed_in_cookie(opts),
         {:ok, body} <- listing_page(ebay_draft_id, cookie, opts),
         {:ok, eps} <- eps_data(body) do
      post_photo(eps, File.read!(path), content_type, cookie, opts)
    end
  end

  def set_first_photo(ebay_draft_id, url, opts \\ []) do
    with {:ok, cookie} <- signed_in_cookie(opts),
         {:ok, body} <- listing_page(ebay_draft_id, cookie, opts),
         {:ok, srt} <- save_token(body),
         {:ok, photos} <- draft_photos(body) do
      save_photos(ebay_draft_id, [url | Enum.drop(photos, 1)], srt, cookie, opts)
    end
  end

  @doc """
  Reads every data module of the draft, without upload tokens.
  """
  def read_draft(ebay_draft_id, opts \\ []) do
    with {:ok, cookie} <- signed_in_cookie(opts),
         {:ok, body} <- listing_page(ebay_draft_id, cookie, opts) do
      modules(body)
    end
  end

  @doc """
  Removes the named optional fields in one save, then reads the draft back to confirm.
  """
  def remove_fields(ebay_draft_id, names, opts \\ [])

  def remove_fields(_ebay_draft_id, [], _opts), do: :ok

  def remove_fields(ebay_draft_id, names, opts) do
    with {:ok, cookie} <- signed_in_cookie(opts),
         {:ok, body} <- listing_page(ebay_draft_id, cookie, opts),
         {:ok, srt} <- draft_token(body),
         :ok <- save_removal(ebay_draft_id, names, srt, cookie, opts),
         {:ok, saved} <- listing_page(ebay_draft_id, cookie, opts) do
      confirm_removed(saved, names)
    end
  end

  def eps_data(body) do
    with {:ok, eps} <- object_after(body, ~s("epsData":)),
         %{"endpoint" => "https://" <> _} <- eps do
      {:ok, eps}
    else
      _ -> {:error, "eBay listing page had no photo upload"}
    end
  end

  @doc """
  The token for the `skip_validation` route, which saves photos.
  """
  def save_token(body) do
    token(body, ~S|"/lstng/api/listing_draft/:draftId(\\d+)/skip_validation":"|)
  end

  @doc """
  The token for the main draft route, which saves every other field.
  """
  def draft_token(body) do
    token(body, ~S|"/lstng/api/listing_draft/:draftId(\\d+)":"|)
  end

  defp token(body, key) do
    text = String.replace(body, "&quot;", ~s("))

    with [_, rest] <- String.split(text, key, parts: 2),
         [token | _] when token != "" <- String.split(rest, ~s("), parts: 2) do
      {:ok, token}
    else
      _ -> {:error, "eBay listing page had no save token"}
    end
  end

  def draft_photos(body) do
    case object_after(body, ~s("photosInput":)) do
      {:ok, %{"photos" => photos}} when is_list(photos) ->
        {:ok, for(%{"url" => url} <- photos, is_binary(url), do: url)}

      _ ->
        {:error, "eBay listing page had no photos"}
    end
  end

  def uploaded_url("VERSION:2;" <> url) do
    url = String.trim(url)

    if ebayimg?(url, "$_"),
      do: {:ok, url},
      else: {:error, "eBay photo upload returned #{url}"}
  end

  def uploaded_url(other),
    do: {:error, "eBay photo upload returned #{String.slice(other, 0, 200)}"}

  defp signed_in_cookie(opts) do
    case cookie_from(opts) do
      cookie when is_binary(cookie) and cookie != "" -> {:ok, cookie}
      _ -> {:error, "eBay cookie is not set"}
    end
  end

  defp post_photo(eps, data, content_type, cookie, opts) do
    fields =
      for key <- ~w(s n v uaek uaes aXRequest wm),
          do: {key, to_string(eps[key] || "")}

    url =
      eps["endpoint"] <>
        "&" <>
        URI.encode_query(
          fileId: 1,
          fId: System.os_time(:millisecond),
          fileSize: byte_size(data),
          ar: "/lstng"
        )

    req_opts =
      Keyword.merge(
        [
          headers: [{"cookie", cookie} | api_headers()],
          form_multipart:
            fields ++ [{"Filedata", {data, filename: "blob", content_type: content_type}}],
          redirect: false,
          decode_body: false,
          retry: false
        ],
        Keyword.delete(opts, :cookie)
      )

    case Req.post(url, req_opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> uploaded_url(body)
      {:ok, %{status: status}} -> {:error, "eBay photo upload returned #{status}"}
      {:error, _reason} -> {:error, "eBay photo upload failed"}
    end
  end

  defp save_photos(ebay_draft_id, pictures, srt, cookie, opts) do
    url =
      "https://www.ebay.com/lstng/api/listing_draft/#{ebay_draft_id}/skip_validation?mode=SellLikeItem"

    put_draft(url, %{pictures: pictures}, srt, cookie, opts)
  end

  defp modules(body) do
    modules =
      @module_key
      |> Regex.scan(body, return: :index)
      |> Enum.reduce(%{}, fn [{start, length}, {name_start, name_length}], modules ->
        name = binary_part(body, name_start, name_length)
        put_module(modules, name, body, start + length)
      end)

    case modules do
      %{"ATTRIBUTES" => _, "TITLE" => _} -> {:ok, modules}
      _ -> {:error, "eBay listing page had no draft"}
    end
  end

  # skip_validation ignores every field but photos, so removals use the main route.
  defp save_removal(ebay_draft_id, names, srt, cookie, opts) do
    url = "https://www.ebay.com/lstng/api/listing_draft/#{ebay_draft_id}?mode=SellLikeItem"

    put_draft(url, OptionalFields.removal(names), srt, cookie, opts)
  end

  # A success status does not prove a field changed.
  defp confirm_removed(body, names) do
    with {:ok, modules} <- modules(body),
         {:ok, kept} <- OptionalFields.still_filled(modules, names) do
      case kept do
        [] -> :ok
        _ -> {:error, "eBay draft kept #{Enum.map_join(kept, ", ", & &1.label)}"}
      end
    end
  end

  defp put_module(modules, name, _body, _start) when is_map_key(modules, name), do: modules

  defp put_module(modules, name, body, start) do
    with {:ok, slice, _next} <- slice_object(body, start),
         {:ok, module} <- Jason.decode(slice) do
      Map.put(modules, name, redact(module))
    else
      _ -> modules
    end
  end

  defp redact(%{} = map) do
    for {key, value} <- map, key not in @secret_keys, into: %{}, do: {key, redact(value)}
  end

  defp redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  defp redact(value), do: value

  defp put_draft(url, fields, srt, cookie, opts) do
    request = %{
      removedFields: [],
      requestId: Ecto.UUID.generate(),
      requestMeta: %{lastDeltaTimestamp: System.os_time(:millisecond)}
    }

    req_opts =
      Keyword.merge(
        [
          headers: [{"cookie", cookie}, {"srt", srt} | api_headers()],
          json: Map.merge(request, fields),
          decode_body: false,
          redirect: false,
          retry: false
        ],
        Keyword.delete(opts, :cookie)
      )

    case Req.put(url, req_opts) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: status}} -> {:error, "eBay draft save returned #{status}"}
      {:error, _reason} -> {:error, "eBay draft save failed"}
    end
  end

  defp api_headers do
    [
      {"accept-language", "en-US,en;q=0.9"},
      {"origin", "https://www.ebay.com"},
      {"referer", "https://www.ebay.com/lstng"},
      {"user-agent", @user_agent}
    ]
  end

  defp object_after(body, key) do
    with {start, len} <- :binary.match(body, key),
         {:ok, slice, _next} <- slice_object(body, start + len),
         {:ok, value} <- Jason.decode(slice) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp request(ebay_draft_id, cookie, opts) do
    with {:ok, body} <- listing_page(ebay_draft_id, cookie, opts) do
      parse(body)
    end
  end

  defp listing_page(ebay_draft_id, cookie, opts) do
    query =
      URI.encode_query(
        draftId: ebay_draft_id,
        mode: "SellLikeItem",
        ReturnURL: @drafts_url
      )

    fetch_page("https://www.ebay.com/lstng?" <> query, cookie, Keyword.delete(opts, :cookie), 5)
  end

  defp fetch_page(_url, _cookie, _opts, 0), do: {:error, "eBay returned too many redirects"}

  defp fetch_page(url, cookie, opts, hops) do
    case get(url, cookie, opts) do
      {:ok, %{status: status, headers: headers}} when status in [301, 302, 303, 307, 308] ->
        follow(url, header(headers, "location"), cookie, opts, hops, status)

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        if challenge_page?(body) do
          {:error, "eBay asked for a browser check"}
        else
          {:ok, body}
        end

      {:ok, %{status: status}} ->
        {:error, "eBay returned #{status}"}

      {:error, _reason} ->
        {:error, "eBay request failed"}
    end
  end

  defp follow(current, location, cookie, opts, hops, status) do
    next = next_url(current, location)

    cond do
      sign_in?(next) ->
        Session.reject(cookie)
        {:error, "eBay session is not signed in"}

      challenge?(next) ->
        {:error, "eBay asked for a browser check"}

      ebay_page?(next) ->
        fetch_page(next, cookie, opts, hops - 1)

      true ->
        {:error, redirect_error(status, next)}
    end
  end

  defp redirect_error(status, url) do
    case URI.parse(to_string(url)) do
      %URI{host: host} when is_binary(host) and host != "" ->
        "eBay returned #{status} to #{host}"

      _ ->
        "eBay returned #{status}"
    end
  end

  defp get(url, cookie, opts) do
    req_opts =
      Keyword.merge(
        [
          headers: [{"cookie", cookie} | @browser_headers],
          redirect: false,
          decode_body: false,
          retry: false
        ],
        opts
      )

    Req.get(url, req_opts)
  end

  defp next_url(current, location) when is_binary(current) and is_binary(location) do
    current
    |> URI.parse()
    |> URI.merge(location)
    |> URI.to_string()
  rescue
    ArgumentError -> nil
  end

  defp next_url(_current, _location), do: nil

  defp ebay_page?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        String.downcase(host) in ["ebay.com", "www.ebay.com"]

      _ ->
        false
    end
  end

  defp ebay_page?(_url), do: false

  defp challenge?(url) when is_binary(url) do
    String.contains?(downcase(URI.parse(url).path), "/splashui/challenge")
  end

  defp challenge?(_url), do: false

  defp challenge_page?(body) do
    String.contains?(body, "Pardon Our Interruption")
  end

  defp sign_in?(url) when is_binary(url) do
    uri = URI.parse(url)
    host = downcase(uri.host)
    path = downcase(uri.path)

    host == "signin.ebay.com" or String.contains?(path, "/signin") or sign_in_query?(uri.query)
  end

  defp sign_in?(_url), do: false

  defp sign_in_query?(nil), do: false

  defp sign_in_query?(query) do
    query
    |> String.downcase()
    |> String.split("&")
    |> Enum.any?(fn pair ->
      pair |> String.split("=") |> hd() == "signin"
    end)
  end

  defp downcase(nil), do: ""
  defp downcase(value), do: String.downcase(value)

  defp header(headers, name) do
    headers
    |> Map.get(name, [])
    |> List.first()
  end

  defp media_type(headers) do
    headers
    |> header("content-type")
    |> case do
      type when is_binary(type) -> type |> String.split(";") |> hd() |> String.trim()
      _ -> nil
    end
  end

  defp json_values(body) do
    scripts =
      ~r/<script\b[^>]*>(.*?)<\/script>/s
      |> Regex.scan(body, capture: :all_but_first)
      |> List.flatten()

    Enum.flat_map([body | scripts], fn text ->
      case Jason.decode(text) do
        {:ok, value} -> [value]
        _ -> objects(text)
      end
    end)
  end

  defp objects(text) do
    if String.contains?(text, "ebayimg") or String.contains?(text, "\"title\"") do
      collect_objects(text, 0, [])
    else
      []
    end
  end

  defp collect_objects(text, offset, acc) when offset >= byte_size(text), do: acc

  defp collect_objects(text, offset, acc) do
    case :binary.match(text, "{\"", scope: {offset, byte_size(text) - offset}) do
      :nomatch ->
        acc

      {start, _len} ->
        collect_slice(text, start, acc)
    end
  end

  defp collect_slice(text, start, acc) do
    case slice_object(text, start) do
      {:ok, slice, next} -> collect_decoded(text, start, next, slice, acc)
      :error -> collect_objects(text, start + 2, acc)
    end
  end

  defp collect_decoded(text, start, next, slice, acc) do
    case Jason.decode(slice) do
      {:ok, value} -> collect_objects(text, next, [value | acc])
      _ -> collect_objects(text, start + 2, acc)
    end
  end

  defp slice_object(text, start) do
    slice_object(text, start, start + 1, byte_size(text), 1, false, false)
  end

  defp slice_object(_text, _start, index, size, _depth, _string?, _escape?) when index >= size,
    do: :error

  defp slice_object(text, start, index, size, depth, string?, escape?) do
    <<char>> = binary_part(text, index, 1)
    advance(text, start, index, size, depth, string?, escape?, char)
  end

  defp advance(text, start, index, size, depth, string?, true, _char) do
    slice_object(text, start, index + 1, size, depth, string?, false)
  end

  defp advance(text, start, index, size, depth, true, false, ?\\) do
    slice_object(text, start, index + 1, size, depth, true, true)
  end

  defp advance(text, start, index, size, depth, true, false, ?") do
    slice_object(text, start, index + 1, size, depth, false, false)
  end

  defp advance(text, start, index, size, depth, true, false, _char) do
    slice_object(text, start, index + 1, size, depth, true, false)
  end

  defp advance(text, start, index, size, depth, false, false, ?") do
    slice_object(text, start, index + 1, size, depth, true, false)
  end

  defp advance(text, start, index, size, depth, false, false, ?{) do
    slice_object(text, start, index + 1, size, depth + 1, false, false)
  end

  defp advance(text, start, index, _size, depth, false, false, ?}) when depth == 1 do
    next = index + 1
    {:ok, binary_part(text, start, next - start), next}
  end

  defp advance(text, start, index, size, depth, false, false, ?}) do
    slice_object(text, start, index + 1, size, depth - 1, false, false)
  end

  defp advance(text, start, index, size, depth, false, false, _char) do
    slice_object(text, start, index + 1, size, depth, false, false)
  end

  defp choose_title([]), do: nil

  defp choose_title(candidates) do
    readable = Enum.reject(candidates, fn {title, _count} -> String.contains?(title, "+") end)
    source = if readable == [], do: candidates, else: readable
    Enum.max_by(source, fn {_title, count} -> count end)
  end

  defp titles(data) do
    walk(data, fn
      %{} = map ->
        case title_value(map["title"] || map["Title"] || map["itemTitle"] || title_field(map)) do
          nil -> nil
          title -> {title, length(image_urls(map))}
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp title_field(%{"name" => "title", "value" => value}), do: value
  defp title_field(_map), do: nil

  defp title_value(value) when is_binary(value) do
    value = String.trim(value)
    if value != "" and String.length(value) <= 80, do: value
  end

  defp title_value(%{"value" => value}), do: title_value(value)
  defp title_value(_), do: nil

  defp image_urls(data) do
    walk(data, fn
      %{"url" => url, "thumbnail" => _} when is_binary(url) ->
        if listing_photo?(url), do: url

      value when is_binary(value) ->
        if stock_image?(value), do: value

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp listing_photo?(url), do: ebayimg?(url, "$_")
  defp stock_image?(url), do: ebayimg?(url, "/images/")

  defp ebayimg?(url, marker) do
    uri = URI.parse(url)

    uri.scheme in ["http", "https"] and is_binary(uri.host) and
      String.ends_with?(uri.host, "ebayimg.com") and String.contains?(uri.path || "", marker)
  end

  defp normalize_url(url) do
    url
    |> String.split("?")
    |> hd()
    |> String.replace(~r/s-l\d+(?=\.)/, "s-l1600")
    |> String.replace(~r/\$_\d+(?=\.)/, "$_57")
  end

  defp walk(data, fun) do
    data
    |> walk(fun, [])
    |> Enum.reverse()
  end

  defp walk(data, fun, acc) do
    acc = if value = fun.(data), do: [value | acc], else: acc

    cond do
      is_map(data) -> Enum.reduce(data, acc, fn {_key, value}, acc -> walk(value, fun, acc) end)
      is_list(data) -> Enum.reduce(data, acc, fn value, acc -> walk(value, fun, acc) end)
      true -> acc
    end
  end
end
