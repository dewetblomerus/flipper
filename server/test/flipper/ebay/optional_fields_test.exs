defmodule Flipper.Ebay.OptionalFieldsTest do
  use ExUnit.Case, async: true

  alias Flipper.Ebay.SellerHub.OptionalFields

  test "offers filled optional specifics, the subtitle, and the UPC" do
    modules =
      modules(
        [
          specific("Color", ["RECOMMENDED"], ["Black"]),
          specific("Features", ["ADDITIONAL"], ["Remote", "Timer"]),
          specific("My note", [], ["Custom"])
        ],
        subtitle: "Works well",
        upc: "036000291452"
      )

    assert {:ok, filled} = OptionalFields.filled(modules)

    assert filled == [
             %{name: "attributes.Color", label: "Color", value: "Black"},
             %{name: "attributes.Features", label: "Features", value: "Remote, Timer"},
             %{name: "attributes.My note", label: "My note", value: "Custom"},
             %{name: "subtitle", label: "Subtitle", value: "Works well"},
             %{name: "universalProductCode", label: "UPC", value: "036000291452"}
           ]
  end

  test "keeps required specifics, Brand, read-only specifics, and empty fields" do
    modules =
      modules([
        specific("Type", ["REQUIRED"], ["Remote"]),
        specific("Brand", ["RECOMMENDED"], ["Acme"]),
        specific("Model", ["ADDITIONAL"], ["X1"]) |> Map.put("readOnly", true),
        specific("Voltage", ["ADDITIONAL"], []),
        specific("Material", ["ADDITIONAL"], nil)
      ])

    assert OptionalFields.filled(modules) == {:ok, []}
  end

  test "still_filled finds a named value even when the field is no longer optional" do
    modules =
      modules(
        [
          specific("Type", ["REQUIRED"], ["Remote"]),
          specific("Model", ["ADDITIONAL"], ["X1"]) |> Map.put("readOnly", true),
          specific("Color", ["RECOMMENDED"], [])
        ],
        subtitle: "Works well"
      )

    names = ["attributes.Type", "attributes.Model", "attributes.Color"]

    assert {:ok, kept} = OptionalFields.still_filled(modules, names)
    assert Enum.map(kept, & &1.label) == ["Type", "Model"]
  end

  test "modules without item specifics are an error" do
    assert {:error, _} = OptionalFields.filled(%{"ATTRIBUTES" => %{}, "TITLE" => %{}})
  end

  test "removal builds the save fields for the named fields" do
    names = ["attributes.Color", "attributes.My note", "subtitle", "universalProductCode"]

    assert OptionalFields.removal(names) == %{
             attributes: %{"Color" => [], "My note" => []},
             subtitle: "",
             removedFields: ["universalProductCode"]
           }

    assert OptionalFields.removal(["subtitle"]) == %{subtitle: ""}
  end

  defp modules(specifics, opts \\ []) do
    upc = %{"name" => "universalProductCode", "value" => opts[:upc]}

    %{
      "ATTRIBUTES" => %{"attributeList" => specifics, "globalTradeItemNumber" => upc},
      "TITLE" => %{"subtitleField" => %{"name" => "subtitle", "value" => opts[:subtitle]}}
    }
  end

  defp specific(label, groups, value) do
    %{"name" => "attributes." <> label, "groups" => groups, "value" => value}
  end
end
