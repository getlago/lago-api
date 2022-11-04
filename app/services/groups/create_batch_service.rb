# frozen_string_literal: true

module Groups
  class CreateBatchService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(billable_metric:, group_params:)
      @billable_metric = billable_metric
      @group_params = group_params

      super
    end

    def call
      return result.validation_failure!(errors: { group: %w[value_is_invalid] }) unless valid_format?

      ActiveRecord::Base.transaction do
        if one_dimension?
          create_groups(group_params[:key], group_params[:values].uniq)
        else
          group_params[:values].each do |value|
            parent_group = billable_metric.groups.create!(key: group_params[:key], value: value[:name])
            create_groups(value[:key], value[:values].uniq, parent_group.id)
          end
        end
      end

      result
    end

    private

    attr_reader :billable_metric, :group_params

    # One dimension:
    # { key: "region", values: ["USA", "EUROPE"] }
    #
    # Two dimensions:
    # {
    #   key: "region",
    #   values: [{
    #     name: "Africa",
    #   	key: "cloud",
    #     values: ["Google cloud", "AWS", "Qovery", "Cloudfare"]
    #   }, {
    #     name: "America",
    #   	key: "cloud",
    #     values: ["Google cloud", "AWS"]
    #   }]
    # }
    def valid_format?
      return false unless group_params[:key].is_a?(String) && group_params[:values].is_a?(Array)
      return true if one_dimension?
      return false unless group_params[:values].all?(Hash)

      group_params[:values].map { |e| [e[:name], e[:key], e[:values]] }.flatten.all?(String)
    end

    def create_groups(key, values, parent_group_id = nil)
      values.each do |value|
        billable_metric.groups.create!(
          key: key,
          value: value,
          parent_group_id: parent_group_id,
        )
      end
    end

    def one_dimension?
      # ie: { key: "region", values: ["USA", "EUROPE"] }
      group_params[:key].is_a?(String) && group_params[:values]&.all?(String)
    end
  end
end
