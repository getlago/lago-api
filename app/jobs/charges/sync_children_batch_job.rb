# frozen_string_literal: true

module Charges
  class SyncChildrenBatchJob < ApplicationJob
    queue_as :default

    def perform(child_ids:, charge:)
      Charges::SyncChildrenBatchService.call!(child_ids:, charge:)
    end
  end
end
