# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ExecuteScheduledOrdersJob, job: true do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let!(:due_order) { create(:order, organization:, customer:, execution_mode: :execute_in_lago, execute_at: 1.hour.ago) }
  let!(:future_order) { create(:order, organization:, customer:, execution_mode: :execute_in_lago, execute_at: 1.hour.from_now) }
  let!(:executed_order) { create(:order, :executed_in_lago, organization:, customer:, execute_at: 1.hour.ago) }
  let!(:failed_order) { create(:order, :failed, organization:, customer:, execute_at: 1.hour.ago) }

  describe ".perform" do
    it "enqueues ExecuteOrderJob only for due, created orders" do
      described_class.perform_now

      expect(Orders::ExecuteOrderJob).to have_been_enqueued.with(due_order)
      expect(Orders::ExecuteOrderJob).not_to have_been_enqueued.with(future_order)
      expect(Orders::ExecuteOrderJob).not_to have_been_enqueued.with(executed_order)
      expect(Orders::ExecuteOrderJob).not_to have_been_enqueued.with(failed_order)
    end
  end
end
