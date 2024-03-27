# frozen_string_literal: true

module Pagination
  extend ActiveSupport::Concern

  private

  PER_PAGE = 100

  def pagination_metadata(records)
    if records.present?
      {
        "current_page" => records.current_page,
        "next_page" => records.next_page,
        "prev_page" => records.prev_page,
        "total_pages" => records.total_pages,
        "total_count" => records.total_count
      }
    else
      {
        "current_page" => 0,
        "next_page" => nil,
        "prev_page" => nil,
        "total_pages" => 0,
        "total_count" => 0
      }
    end
  end
end
