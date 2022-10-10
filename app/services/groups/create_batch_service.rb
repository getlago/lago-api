# frozen_string_literal: true

module Groups
  class CreateBatchService
    def self.call(...)
      new(...).call
    end

    def initialize(billable_metric:, group_params:)
      @billable_metric = billable_metric
      @group_params = group_params.with_indifferent_access
    end

    def call
      # TODO: return errors
      ActiveRecord::Base.transaction do
        if one_dimension?
          create_groups(group_params[:key], group_params[:values])
        else
          group_params[:values].each do |value|
            parent_group = billable_metric.groups.create!(key: group_params[:key], value: value[:name])
            create_groups(value[:key], value[:values], parent_group.id)
          end
        end
      end
    end

    private

    attr_reader :billable_metric, :group_params

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
      group_params[:values].all?(String)
    end
  end
end
