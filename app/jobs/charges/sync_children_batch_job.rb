# frozen_string_literal: true

module Charges
  class SyncChildrenBatchJob < ApplicationJob
    queue_as :default

    def perform(children_plans_ids:, charge:)
      Charges::SyncChildrenBatchService.call!(children_plans_ids:, charge:)
    end
  end
end
