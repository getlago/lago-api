# frozen_string_literal: true

module DataApi
  class RevenueStreamsService < BaseService
    Result = BaseResult[:revenue_streams]

    def call
      return result.forbidden_failure! unless License.premium?

      data_revenue_streams = http_client.get(headers:, params:)

      result.revenue_streams = format_revenue_streams(data_revenue_streams)
      result
    end

    private

    def action_path
      "revenue_streams/#{organization.id}/"
    end

    def format_revenue_streams(data_revenue_streams)
      data_revenue_streams.map do |revenue_stream|
        revenue_stream["currency"] = revenue_stream.delete("amount_currency")
        revenue_stream["from_date"] = revenue_stream.delete("start_of_period_dt")
        revenue_stream["to_date"] = revenue_stream.delete("end_of_period_dt")
        revenue_stream
      end
    end
  end
end
