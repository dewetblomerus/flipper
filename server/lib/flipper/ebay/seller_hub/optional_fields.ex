defmodule Flipper.Ebay.SellerHub.OptionalFields do
  @moduledoc """
  The sell-similar fields a person may remove from a draft: Recommended and Additional item
  specifics, the subtitle, and the UPC. Required specifics, Brand, and every other field stay.

  A field is identified by the name eBay saves it under.
  """

  @attribute "attributes."
  @subtitle "subtitle"
  @upc "universalProductCode"
  @kept [@attribute <> "Brand"]

  @doc """
  Takes the draft's modules and returns each filled optional field as
  `%{name: name, label: label, value: value}`.
  """
  def filled(modules), do: fields(modules, &optional?/1)

  @doc """
  Returns the named fields that still hold a value, including any no longer optional.
  """
  def still_filled(modules, names) do
    with {:ok, fields} <- fields(modules, fn _specific -> true end) do
      {:ok, Enum.filter(fields, &(&1.name in names))}
    end
  end

  @doc """
  Returns the save fields that remove the named fields.
  """
  def removal(names) do
    attributes = for @attribute <> label <- names, into: %{}, do: {label, []}

    %{}
    |> put_if(attributes != %{}, :attributes, attributes)
    |> put_if(@subtitle in names, :subtitle, "")
    # eBay keeps a UPC that is saved as "". Naming it in removedFields empties it.
    |> put_if(@upc in names, :removedFields, [@upc])
  end

  defp fields(
         %{
           "ATTRIBUTES" => %{"attributeList" => specifics} = attributes,
           "TITLE" => title
         },
         include?
       )
       when is_list(specifics) do
    {:ok, specifics(specifics, include?) ++ subtitle(title) ++ upc(attributes)}
  end

  defp fields(_modules, _include?), do: {:error, "eBay draft had no item specifics or title"}

  defp specifics(specifics, include?) do
    for %{"name" => @attribute <> label = name} = specific <- specifics,
        include?.(specific),
        value = text(specific["value"]),
        do: %{name: name, label: label, value: value}
  end

  defp optional?(specific) do
    specific["name"] not in @kept and
      "REQUIRED" not in List.wrap(specific["groups"]) and
      specific["readOnly"] != true
  end

  defp subtitle(title) do
    case text(get_in(title, ["subtitleField", "value"])) do
      nil -> []
      value -> [%{name: @subtitle, label: "Subtitle", value: value}]
    end
  end

  defp upc(attributes) do
    case find_upc(attributes) do
      nil -> []
      value -> [%{name: @upc, label: "UPC", value: value}]
    end
  end

  defp find_upc(%{"name" => @upc} = field), do: text(field["value"])
  defp find_upc(%{} = map), do: map |> Map.values() |> Enum.find_value(&find_upc/1)
  defp find_upc(list) when is_list(list), do: Enum.find_value(list, &find_upc/1)
  defp find_upc(_value), do: nil

  # The value as one line, or nil when the field is empty.
  defp text(value) do
    case value |> List.wrap() |> Enum.reject(&(&1 in [nil, ""])) do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end

  defp put_if(map, true, key, value), do: Map.put(map, key, value)
  defp put_if(map, false, _key, _value), do: map
end
