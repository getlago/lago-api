# frozen_string_literal: true

module UsageMonitoring
  class ProcessActivityService < BaseService
    Result = BaseResult

    def initialize(organization:, subscription_external_id:)
      @organization = organization
      @subscription_external_id = subscription_external_id
    end

    def call
      Alert.where(subscription_external_id:, organization:).find_each do |alert|
        ProcessAlertService.call(alert:) # TODO: make this async with a job
      end

      result
    end

    private

    attr_reader :organization, :subscription_external_id
  end
end
