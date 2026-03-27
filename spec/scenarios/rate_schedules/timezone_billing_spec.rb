# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Timezone Billing" do
  include_context "with rate schedule billing"

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
        [DateTime.new(2024, 2, 29, 19, 0)] # Feb 29 19:00 UTC = Mar 1 00:30 IST
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
        [DateTime.new(2024, 3, 1, 5, 0)] # Mar 1 05:00 UTC = Mar 1 00:00 COT
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 2, 5, 0)] # Mar 2 05:00 UTC = Mar 2 00:00 COT
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with weekly anniversary billing" do
    let(:billing_interval_unit) { "week" }

    context "with UTC+ timezone (Asia/Kolkata, +05:30)" do
      let(:timezone) { "Asia/Kolkata" }
      let(:subscription_time) { DateTime.new(2024, 2, 1) } # Thursday

      # next_billing_date = Feb 8 (Thursday, 1 week later)
      let(:before_billing_times) do
        [DateTime.new(2024, 2, 7, 18, 0)] # Feb 7 18:00 UTC = Feb 7 23:30 IST
      end
      let(:billing_times) do
        [DateTime.new(2024, 2, 7, 19, 0)] # Feb 7 19:00 UTC = Feb 8 00:30 IST
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 2, 8, 19, 0)] # Feb 8 19:00 UTC = Feb 9 00:30 IST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end

    context "with UTC- timezone (America/New_York, -05:00)" do
      let(:timezone) { "America/New_York" }
      let(:subscription_time) { DateTime.new(2024, 2, 1) } # Thursday

      # next_billing_date = Feb 8
      let(:before_billing_times) do
        [DateTime.new(2024, 2, 8, 4, 0)] # Feb 8 04:00 UTC = Feb 7 23:00 EST
      end
      let(:billing_times) do
        [DateTime.new(2024, 2, 8, 5, 0)] # Feb 8 05:00 UTC = Feb 8 00:00 EST
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 2, 9, 5, 0)] # Feb 9 05:00 UTC = Feb 9 00:00 EST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with yearly anniversary billing" do
    let(:billing_interval_unit) { "year" }

    context "with UTC+ timezone (Asia/Tokyo, +09:00)" do
      let(:timezone) { "Asia/Tokyo" }
      let(:subscription_time) { DateTime.new(2024, 1, 15) }

      # next_billing_date = Jan 15, 2025
      let(:before_billing_times) do
        [DateTime.new(2025, 1, 14, 14, 0)] # Jan 14 14:00 UTC = Jan 14 23:00 JST
      end
      let(:billing_times) do
        [DateTime.new(2025, 1, 14, 15, 0)] # Jan 14 15:00 UTC = Jan 15 00:00 JST
      end
      let(:after_billing_times) do
        [DateTime.new(2025, 1, 15, 15, 0)] # Jan 15 15:00 UTC = Jan 16 00:00 JST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end

    context "with UTC- timezone (Pacific/Honolulu, -10:00)" do
      let(:timezone) { "Pacific/Honolulu" }
      let(:subscription_time) { DateTime.new(2024, 1, 15) }

      # next_billing_date = Jan 15, 2025
      let(:before_billing_times) do
        [DateTime.new(2025, 1, 15, 9, 0)] # Jan 15 09:00 UTC = Jan 14 23:00 HST
      end
      let(:billing_times) do
        [DateTime.new(2025, 1, 15, 10, 0)] # Jan 15 10:00 UTC = Jan 15 00:00 HST
      end
      let(:after_billing_times) do
        [DateTime.new(2025, 1, 16, 10, 0)] # Jan 16 10:00 UTC = Jan 16 00:00 HST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with monthly calendar billing" do
    let(:billing_interval_unit) { "month" }
    let(:prorated) { true }

    context "with UTC+ timezone (Europe/Paris, +01:00)" do
      let(:timezone) { "Europe/Paris" }
      let(:subscription_time) { DateTime.new(2024, 2, 15) }
      let(:anchor_date) { Date.new(2024, 3, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 2, 29, 22, 0)] # Feb 29 22:00 UTC = Feb 29 23:00 CET
      end
      let(:billing_times) do
        [DateTime.new(2024, 2, 29, 23, 0)] # Feb 29 23:00 UTC = Mar 1 00:00 CET
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 1, 23, 0)] # Mar 1 23:00 UTC = Mar 2 00:00 CET
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end

    context "with UTC- timezone (America/Bogota, -05:00)" do
      let(:timezone) { "America/Bogota" }
      let(:subscription_time) { DateTime.new(2024, 2, 15) }
      let(:anchor_date) { Date.new(2024, 3, 1) }

      let(:before_billing_times) do
        [DateTime.new(2024, 3, 1, 4, 0)] # Mar 1 04:00 UTC = Feb 29 23:00 COT
      end
      let(:billing_times) do
        [DateTime.new(2024, 3, 1, 5, 0)] # Mar 1 05:00 UTC = Mar 1 00:00 COT
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 2, 5, 0)] # Mar 2 05:00 UTC = Mar 2 00:00 COT
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with quarterly calendar billing" do
    let(:billing_interval_unit) { "month" }
    let(:billing_interval_count) { 3 }
    let(:prorated) { true }

    context "with UTC+ timezone (Asia/Kolkata, +05:30)" do
      let(:timezone) { "Asia/Kolkata" }
      let(:subscription_time) { DateTime.new(2024, 2, 1) }
      let(:anchor_date) { Date.new(2024, 4, 1) }

      # next_billing_date = Apr 1
      let(:before_billing_times) do
        [DateTime.new(2024, 3, 31, 18, 0)] # Mar 31 18:00 UTC = Mar 31 23:30 IST
      end
      let(:billing_times) do
        [DateTime.new(2024, 3, 31, 19, 0)] # Mar 31 19:00 UTC = Apr 1 00:30 IST
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 4, 1, 19, 0)] # Apr 1 19:00 UTC = Apr 2 00:30 IST
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end

  context "with DST transition" do
    let(:billing_interval_unit) { "month" }

    # Europe/Paris switches to CEST (+02:00) on Mar 31, 2024
    context "with billing day near DST switch (Europe/Paris)" do
      let(:timezone) { "Europe/Paris" }
      let(:subscription_time) { DateTime.new(2024, 2, 28) }

      # next_billing_date = Mar 28 (before DST switch on Mar 31)
      let(:before_billing_times) do
        [DateTime.new(2024, 3, 27, 22, 0)] # Mar 27 22:00 UTC = Mar 27 23:00 CET (+01:00)
      end
      let(:billing_times) do
        [DateTime.new(2024, 3, 27, 23, 0)] # Mar 27 23:00 UTC = Mar 28 00:00 CET (+01:00)
      end
      let(:after_billing_times) do
        [DateTime.new(2024, 3, 28, 22, 0)] # Mar 28 22:00 UTC = Mar 29 00:00 CEST (+02:00)
      end

      it_behaves_like "a rate schedule billing without duplicated invoices"
    end
  end
end
