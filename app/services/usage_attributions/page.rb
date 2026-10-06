# frozen_string_literal: true

module UsageAttributions
  Page = Data.define(:current_page, :limit_value, :total_count) do
    def self.from_query_result(result)
      new(current_page: (result.offset / result.limit) + 1, limit_value: result.limit, total_count: result.groups_count)
    end

    def total_pages
      (total_count.to_f / limit_value).ceil
    end
  end
end
