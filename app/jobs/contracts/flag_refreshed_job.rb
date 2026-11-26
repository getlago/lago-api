# frozen_string_literal: true

module Contracts
  class FlagRefreshedJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"])
        :alerts_high_priority
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(organization_id, external_contract_id)
      Contracts::FlagRefreshedService.call!(organization_id:, external_contract_id:)
    end
  end
end
