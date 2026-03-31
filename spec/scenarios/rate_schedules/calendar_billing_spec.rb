# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Calendar Billing" do
  include_context "with rate schedule billing"

  let(:prorated) { true }

  # Calendar mode: anchor_date is set, prorated: true
  # First billing = anchor_date (stub), then full periods from anchor.
  # Example: signup March 15, anchor March 20 → stub billed March 20,
  #          then full periods April 20, May 20, etc.

  context "with weekly billing interval" do
    let(:billing_interval_unit) { "week" }

    context "when signup is mid-week" do
      # Signup Tuesday Feb 6, anchor Thursday Feb 8 (same weekday alignment)
      let(:subscription_time) { DateTime.new(2024, 2, 6) }
      let(:billing_anchor_date) { Date.new(2024, 2, 8) } # Thursday

      # First billing = anchor (Feb 8, stub for 2 days)
      let(:before_billing_times) { [DateTime.new(2024, 2, 7)] }
      let(:billing_times) { [DateTime.new(2024, 2, 8, 1), DateTime.new(2024, 2, 8, 12)] }
      let(:after_billing_times) { [DateTime.new(2024, 2, 9)] }
      let(:consecutive_billing_times) do
        [
          DateTime.new(2024, 2, 8, 12),  # stub billing at anchor
          DateTime.new(2024, 2, 15, 12), # +1 week
          DateTime.new(2024, 2, 22, 12)  # +2 weeks
        ]
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
      it_behaves_like "a rate schedule billing on consecutive cycles"
    end
  end

  context "with monthly billing interval" do
    let(:billing_interval_unit) { "month" }

    context "when signup is mid-month" do
      # Signup March 15, anchor March 20 → bills on the 20th
      let(:subscription_time) { DateTime.new(2024, 3, 15) }
      let(:billing_anchor_date) { Date.new(2024, 3, 20) }

      let(:before_billing_times) { [DateTime.new(2024, 3, 19)] }
      let(:billing_times) { [DateTime.new(2024, 3, 20, 1), DateTime.new(2024, 3, 20, 12)] }
      let(:after_billing_times) { [DateTime.new(2024, 3, 21)] }
      let(:consecutive_billing_times) do
        [
          DateTime.new(2024, 3, 20, 12),  # stub billing at anchor
          DateTime.new(2024, 4, 20, 12),  # +1 month
          DateTime.new(2024, 5, 20, 12)   # +2 months
        ]
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
      it_behaves_like "a rate schedule billing on consecutive cycles"
    end

    context "when anchor is 1st of month (classic calendar)" do
      # Signup Feb 10, anchor March 1 → bills on the 1st
      let(:subscription_time) { DateTime.new(2024, 2, 10) }
      let(:billing_anchor_date) { Date.new(2024, 3, 1) }

      let(:before_billing_times) { [DateTime.new(2024, 2, 28)] }
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
  end

  context "with quarterly billing interval (month count: 3)" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 3 }

    # Signup Feb 1, anchor April 1 → bills on April 1, July 1, Oct 1
    let(:subscription_time) { DateTime.new(2024, 2, 1) }
    let(:billing_anchor_date) { Date.new(2024, 4, 1) }

    let(:before_billing_times) { [DateTime.new(2024, 3, 15), DateTime.new(2024, 3, 31)] }
    let(:billing_times) { [DateTime.new(2024, 4, 1, 1), DateTime.new(2024, 4, 1, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 4, 2)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 4, 1, 12),
        DateTime.new(2024, 7, 1, 12),
        DateTime.new(2024, 10, 1, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with semiannual billing interval (month count: 6)" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 6 }

    # Signup Jan 15, anchor July 1 → bills on July 1, Jan 1
    let(:subscription_time) { DateTime.new(2024, 1, 15) }
    let(:billing_anchor_date) { Date.new(2024, 7, 1) }

    let(:before_billing_times) { [DateTime.new(2024, 5, 1), DateTime.new(2024, 6, 30)] }
    let(:billing_times) { [DateTime.new(2024, 7, 1, 1), DateTime.new(2024, 7, 1, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 7, 2)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 7, 1, 12),
        DateTime.new(2025, 1, 1, 12),
        DateTime.new(2025, 7, 1, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with yearly billing interval" do
    let(:billing_interval_unit) { "year" }

    # Signup March 15, anchor June 1 → bills on June 1 each year
    let(:subscription_time) { DateTime.new(2024, 3, 15) }
    let(:billing_anchor_date) { Date.new(2024, 6, 1) }

    let(:before_billing_times) { [DateTime.new(2024, 5, 31)] }
    let(:billing_times) { [DateTime.new(2024, 6, 1, 1), DateTime.new(2024, 6, 1, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 6, 2)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 6, 1, 12),
        DateTime.new(2025, 6, 1, 12),
        DateTime.new(2026, 6, 1, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end

  context "with anchor + prorated: false (ignores anchor, bills from signup)" do
    let(:prorated) { false }
    let(:billing_interval_unit) { "month" }

    # Signup March 15, anchor March 20, prorated: false
    # → bills from signup date (March 15), ignores anchor entirely
    let(:subscription_time) { DateTime.new(2024, 3, 15) }
    let(:billing_anchor_date) { Date.new(2024, 3, 20) }

    let(:before_billing_times) { [DateTime.new(2024, 4, 14)] }
    let(:billing_times) { [DateTime.new(2024, 4, 15, 1), DateTime.new(2024, 4, 15, 12)] }
    let(:after_billing_times) { [DateTime.new(2024, 4, 16)] }
    let(:consecutive_billing_times) do
      [
        DateTime.new(2024, 4, 15, 12),
        DateTime.new(2024, 5, 15, 12),
        DateTime.new(2024, 6, 15, 12)
      ]
    end

    it_behaves_like "a rate schedule billing without duplicated invoices"
    it_behaves_like "a rate schedule billing on consecutive cycles"
  end
end
