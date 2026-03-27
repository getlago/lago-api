# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Timezone Billing" do
  include_context "rate schedule billing"

  let(:customer) { create(:customer, organization:, currency: "EUR", timezone:) }

  context "with monthly anniversary billing" do
    let(:billing_interval_unit) { "month" }

    context "with UTC+ timezone (Asia/Kolkata, +05:30)" do
      let(:timezone) { "Asia/Kolkata" }
      let(:subscription_time) { DateTime.new(2024, 2, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 2, 29, 18, 0)] # Feb 29 18:00 UTC = Feb 29 23:30 IST
      end
      let(:billing_times) do
        [
          DateTime.new(2024, 2, 29, 19, 0), # Feb 29 19:00 UTC = Mar 1 00:30 IST
          DateTime.new(2024, 3, 1, 0, 0),   # Mar 1 00:00 UTC  = Mar 1 05:30 IST
          DateTime.new(2024, 3, 1, 18, 0)   # Mar 1 18:00 UTC  = Mar 1 23:30 IST
        ]
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 1, 19, 0)] # Mar 1 19:00 UTC = Mar 2 00:30 IST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end

    context "with UTC- timezone (America/Bogota, -05:00)" do
      let(:timezone) { "America/Bogota" }
      let(:subscription_time) { DateTime.new(2024, 2, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 3, 1, 4, 0)] # Mar 1 04:00 UTC = Feb 29 23:00 COT
      end
      let(:billing_times) do
        [
          DateTime.new(2024, 3, 1, 5, 0),  # Mar 1 05:00 UTC = Mar 1 00:00 COT
          DateTime.new(2024, 3, 1, 12, 0),  # Mar 1 12:00 UTC = Mar 1 07:00 COT
          DateTime.new(2024, 3, 2, 4, 0)    # Mar 2 04:00 UTC = Mar 1 23:00 COT
        ]
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 2, 5, 0)] # Mar 2 05:00 UTC = Mar 2 00:00 COT
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with monthly calendar billing" do
    let(:billing_interval_unit) { "month" }
    let(:prorated) { true }

    context "with UTC+ timezone (Europe/Paris, +01:00/+02:00)" do
      let(:timezone) { "Europe/Paris" }
      # Signup Feb 15, anchor March 1
      let(:subscription_time) { DateTime.new(2024, 2, 15) }
      let(:anchor_date) { Date.new(2024, 3, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 2, 29, 22, 0)] # Feb 29 22:00 UTC = Feb 29 23:00 CET
      end
      let(:billing_times) do
        [
          DateTime.new(2024, 2, 29, 23, 0), # Feb 29 23:00 UTC = Mar 1 00:00 CET
          DateTime.new(2024, 3, 1, 12, 0),  # Mar 1 12:00 UTC  = Mar 1 13:00 CET
          DateTime.new(2024, 3, 1, 22, 0)   # Mar 1 22:00 UTC  = Mar 1 23:00 CET
        ]
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 1, 23, 0)] # Mar 1 23:00 UTC = Mar 2 00:00 CET
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end

    context "with UTC- timezone (America/Bogota, -05:00)" do
      let(:timezone) { "America/Bogota" }
      # Signup Feb 15, anchor March 1
      let(:subscription_time) { DateTime.new(2024, 2, 15) }
      let(:anchor_date) { Date.new(2024, 3, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 3, 1, 4, 0)] # Mar 1 04:00 UTC = Feb 29 23:00 COT
      end
      let(:billing_times) do
        [
          DateTime.new(2024, 3, 1, 5, 0),  # Mar 1 05:00 UTC = Mar 1 00:00 COT
          DateTime.new(2024, 3, 1, 12, 0),  # Mar 1 12:00 UTC = Mar 1 07:00 COT
          DateTime.new(2024, 3, 2, 4, 0)    # Mar 2 04:00 UTC = Mar 1 23:00 COT
        ]
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 2, 5, 0)] # Mar 2 05:00 UTC = Mar 2 00:00 COT
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end
end