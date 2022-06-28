module Pagination
  extend ActiveSupport::Concern

  private

  PER_PAGE = 10.freeze

  def pagination_metadata(records)
    if records.present?
      {
        'currentPage' => records.current_page,
        'nextPage' => records.next_page,
        'prevPage' => records.prev_page,
        'totalPages' => records.total_pages,
        'totalCount' => records.total_count
      }
    else
      {
        'currentPage' => 0,
        'nextPage' => nil,
        'prevPage' => nil,
        'totalPages' => 0,
        'totalCount' => 0
      }
     end
  end
end