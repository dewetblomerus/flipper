defmodule Flipper.Workers.EbayPriority do
  @moduledoc """
  Job priorities in `ebay_cookie_requests`. Lower runs first.
  """

  def write, do: 0
  def person_read, do: 1
  def unattended_read, do: 2
end
