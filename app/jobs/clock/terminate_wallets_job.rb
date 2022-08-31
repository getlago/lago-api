# frozen_string_literal: true

module Clock
  class TerminateWalletsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Wallets::TerminateService.new.terminate_all_expired
    end
  end
end
