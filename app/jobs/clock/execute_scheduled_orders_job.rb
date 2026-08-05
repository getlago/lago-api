# frozen_string_literal: true

module Clock
  class ExecuteScheduledOrdersJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Order.executable.find_each do |order|
        Orders::ExecuteOrderJob.perform_later(order)
      end
    end
  end
end
