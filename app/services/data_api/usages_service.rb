# frozen_string_literal: true

module DataApi
  class UsagesService < DataApi::BaseService
    Result = BaseResult[:usages]

    def call
      result.usages = http_client.get(headers:, params: filtered_params)
      result
    end

    private

    def filtered_params
      if License.premium?
        params.dup.tap do |filtered|
          filtered[:time_granularity] ||= "daily"
        end
      else
        {
          time_granularity: "daily",
          start_of_period_dt: Date.current - 30.days
        }
      end
    end

    def action_path
      "usages/#{organization.id}/"
    end
  end
end
