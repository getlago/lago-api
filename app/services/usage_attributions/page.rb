# frozen_string_literal: true

module UsageAttributions
  Page = Data.define(:current_page, :limit_value, :total_count) do
    def total_pages
      (total_count.to_f / limit_value).ceil
    end
  end
end
