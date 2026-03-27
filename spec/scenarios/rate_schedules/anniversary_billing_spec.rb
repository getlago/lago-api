# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Anniversary Billing" do
  include_context "rate schedule billing"

  context "with daily billing interval" do
    let(:billing_interval_unit) { "day" }
    let(:subscription_time) { DateTime.new(2024, 2, 1) }

    let(:before_billing_times) { [DateTime.new(2024, 2, 1, 23, 0)] }
    let(:billing_times) { [DateTime.new(2024, 2, 2, 1), DateTime.new(2024, 2, 2, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 2, 2, 18)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 2, 2, 12),
        DateTime.new(2024, 2, 3, 12),
        DateTime.new(2024, 2, 4, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with weekly billing interval" do
    let(:billing_interval_unit) { "week" }
    let(:subscription_time) { DateTime.new(2024, 2, 1) } # Thursday

    let(:before_billing_times) { [DateTime.new(2024, 2, 5)] }
    let(:billing_times) { [DateTime.new(2024, 2, 8, 1), DateTime.new(2024, 2, 8, 12)] } # next Thursday
    let(:after_billing_times) { [DateTime.new(2024, 2, 9)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 2, 8, 12),
        DateTime.new(2024, 2, 15, 12),
        DateTime.new(2024, 2, 22, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with monthly billing interval" do
    let(:billing_interval_unit) { "month" }
    let(:subscription_time) { DateTime.new(2024, 2, 1) }

    let(:before_billing_times) { [DateTime.new(2024, 2, 15)] }
    let(:billing_times) { [DateTime.new(2024, 3, 1, 1), DateTime.new(2024, 3, 1, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 3, 2)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 3, 1, 12),
        DateTime.new(2024, 4, 1, 12),
        DateTime.new(2024, 5, 1, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with quarterly billing interval (month count: 3)" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 3 }
    let(:subscription_time) { DateTime.new(2024, 1, 15) }

    let(:before_billing_times) { [DateTime.new(2024, 3, 15), DateTime.new(2024, 4, 14)] }
    let(:billing_times) { [DateTime.new(2024, 4, 15, 1), DateTime.new(2024, 4, 15, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 4, 16)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 4, 15, 12),  # +3 months
        DateTime.new(2024, 7, 15, 12),  # +6 months
        DateTime.new(2024, 10, 15, 12)  # +9 months
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with semiannual billing interval (month count: 6)" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 6 }
    let(:subscription_time) { DateTime.new(2024, 1, 10) }

    let(:before_billing_times) { [DateTime.new(2024, 5, 10), DateTime.new(2024, 7, 9)] }
    let(:billing_times) { [DateTime.new(2024, 7, 10, 1), DateTime.new(2024, 7, 10, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 7, 11)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 7, 10, 12),  # +6 months
        DateTime.new(2025, 1, 10, 12),  # +12 months
        DateTime.new(2025, 7, 10, 12)   # +18 months
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with yearly billing interval" do
    let(:billing_interval_unit) { "year" }
    let(:subscription_time) { DateTime.new(2024, 3, 15) }

    let(:before_billing_times) { [DateTime.new(2024, 12, 31), DateTime.new(2025, 3, 14)] }
    let(:billing_times) { [DateTime.new(2025, 3, 15, 1), DateTime.new(2025, 3, 15, 12)] }
    let(:after_billing_times) { [DateTime.new(2025, 3, 16)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2025, 3, 15, 12),
        DateTime.new(2026, 3, 15, 12),
        DateTime.new(2027, 3, 15, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with billing_interval_count of 2 months" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 2 }
    let(:subscription_time) { DateTime.new(2024, 1, 15) }

    let(:before_billing_times) { [DateTime.new(2024, 2, 15), DateTime.new(2024, 3, 14)] }
    let(:billing_times) { [DateTime.new(2024, 3, 15, 1), DateTime.new(2024, 3, 15, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 3, 16)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 3, 15, 12),
        DateTime.new(2024, 5, 15, 12),
        DateTime.new(2024, 7, 15, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with month-end edge cases" do
    let(:billing_interval_unit) { "month" }

    context "when started on the 31st" do
      let(:subscription_time) { DateTime.new(2024, 1, 31) }

      # Jan 31 + 1 month = Feb 29 (2024 is leap), + 2 = Mar 31, + 3 = Apr 30, etc.
      let(:consecutive_billing_times) do
        [
          DateTime.new(2024, 2, 29, 12),
          DateTime.new(2024, 3, 31, 12),
          DateTime.new(2024, 4, 30, 12),
          DateTime.new(2024, 5, 31, 12)
        ]
      end

      it_behaves_like "a rate schedule billing on consecutive cycles"
    end

    context "when started on Feb 29 (leap year)" do
      let(:subscription_time) { DateTime.new(2024, 2, 29) }

      let(:consecutive_billing_times) do
        [
          DateTime.new(2024, 3, 29, 12),
          DateTime.new(2024, 4, 29, 12),
          DateTime.new(2024, 5, 29, 12)
        ]
      end

      it_behaves_like "a rate schedule billing on consecutive cycles"
    end
  end
end