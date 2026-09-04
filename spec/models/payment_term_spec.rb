# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerm do
  let(:issuing_date) { Date.new(2026, 7, 15) }

  describe ".from_h" do
    it "builds a term from a jsonb-style hash with string keys" do
      term = described_class.from_h("term_type" => "net", "days" => 30)

      expect(term.term_type).to eq("net")
      expect(term.days).to eq(30)
    end

    it "builds a term from a hash with symbol keys" do
      term = described_class.from_h(term_type: "day_of_month", day_of_month: 15, month_offset: 2)

      expect(term.term_type).to eq("day_of_month")
      expect(term.day_of_month).to eq(15)
      expect(term.month_offset).to eq(2)
    end

    it "defaults month_offset to 1 for day_of_month" do
      term = described_class.from_h(term_type: "day_of_month", day_of_month: 15)

      expect(term.month_offset).to eq(1)
    end
  end

  describe ".from_net_payment_term" do
    it "builds a net term from the legacy alias" do
      expect(described_class.from_net_payment_term(0)&.to_h)
        .to eq("term_type" => "net", "days" => 0)
      expect(described_class.from_net_payment_term(30)&.to_h)
        .to eq("term_type" => "net", "days" => 30)
    end

    it "returns nil when the legacy alias is cleared" do
      expect(described_class.from_net_payment_term(nil)).to be_nil
    end
  end

  describe "#to_h" do
    it "serializes only the fields carried by the term type" do
      expect(described_class.from_h(term_type: "due_on_receipt").to_h)
        .to eq("term_type" => "due_on_receipt")
      expect(described_class.from_h(term_type: "net", days: 30).to_h)
        .to eq("term_type" => "net", "days" => 30)
      expect(described_class.from_h(term_type: "end_of_month").to_h)
        .to eq("term_type" => "end_of_month")
      expect(described_class.from_h(term_type: "day_of_month", day_of_month: 31).to_h)
        .to eq("term_type" => "day_of_month", "day_of_month" => 31, "month_offset" => 1)
    end

    it "round-trips through from_h" do
      hash = {"term_type" => "days_end_of_month", "days" => 30}

      expect(described_class.from_h(hash).to_h).to eq(hash)
    end

    it "drops fields not carried by the term type" do
      term = described_class.from_h(term_type: "end_of_month", days: 5, day_of_month: 10, month_offset: 2)

      expect(term.to_h).to eq("term_type" => "end_of_month")
    end
  end

  describe "#net_payment_term_alias" do
    it "returns N for net, 0 for due_on_receipt and nil for the four new types" do
      expect(described_class.from_h(term_type: "net", days: 30).net_payment_term_alias).to eq(30)
      expect(described_class.from_h(term_type: "due_on_receipt").net_payment_term_alias).to eq(0)
      expect(described_class.from_h(term_type: "end_of_month").net_payment_term_alias).to be_nil
      expect(described_class.from_h(term_type: "net_end_of_month", days: 30).net_payment_term_alias).to be_nil
      expect(described_class.from_h(term_type: "days_end_of_month", days: 30).net_payment_term_alias).to be_nil
      expect(described_class.from_h(term_type: "day_of_month", day_of_month: 15).net_payment_term_alias).to be_nil
    end
  end

  describe "#due_date_for" do
    context "when due_on_receipt" do
      it "returns the issuing date" do
        term = described_class.from_h(term_type: "due_on_receipt")

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 15))
      end
    end

    context "when the issuing date is a Time" do
      it "coerces to a Date so days are added as days, not seconds" do
        term = described_class.from_h(term_type: "net", days: 30)

        due_date = term.due_date_for(Time.zone.parse("2026-07-15 10:30:00"))

        expect(due_date).to eq(Date.new(2026, 8, 14))
        expect(due_date).to be_a(Date)
      end
    end

    context "when the term type is unknown" do
      it "raises an ArgumentError" do
        term = described_class.from_h(term_type: "fortnightly")

        expect { term.due_date_for(issuing_date) }
          .to raise_error(ArgumentError, "unknown term_type: fortnightly")
      end
    end

    context "when net" do
      it "adds N days to the issuing date" do
        term = described_class.from_h(term_type: "net", days: 30)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 14))
      end

      it "equals due_on_receipt when days is 0" do
        term = described_class.from_h(term_type: "net", days: 0)

        expect(term.due_date_for(issuing_date)).to eq(issuing_date)
      end
    end

    context "when end_of_month" do
      it "returns the last day of the issuing month" do
        term = described_class.from_h(term_type: "end_of_month")

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 31))
      end

      it "handles February in a leap year" do
        term = described_class.from_h(term_type: "end_of_month")

        expect(term.due_date_for(Date.new(2028, 2, 10))).to eq(Date.new(2028, 2, 29))
      end
    end

    context "when net_end_of_month (US)" do
      it "goes to end of month, then adds N days" do
        term = described_class.from_h(term_type: "net_end_of_month", days: 30)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 30))
      end

      it "equals end_of_month when days is 0" do
        term = described_class.from_h(term_type: "net_end_of_month", days: 0)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 31))
      end
    end

    context "when days_end_of_month (EU)" do
      it "adds N days, then goes to end of month" do
        term = described_class.from_h(term_type: "days_end_of_month", days: 30)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 31))
      end

      it "equals end_of_month when days is 0" do
        term = described_class.from_h(term_type: "days_end_of_month", days: 0)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 31))
      end
    end

    context "when the two end-of-month types share the same days value" do
      it "produces diverging due dates because the order of operations differs" do
        us = described_class.from_h(term_type: "net_end_of_month", days: 30)
        eu = described_class.from_h(term_type: "days_end_of_month", days: 30)

        expect(us.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 30))
        expect(eu.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 31))
      end
    end

    context "when day_of_month" do
      it "returns the Dth day of the month after month_offset" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 15)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 15))
      end

      it "supports a month_offset greater than 1" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 15, month_offset: 2)

        expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 9, 15))
      end

      it "clamps the day to the last day of a shorter month" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 31)

        expect(term.due_date_for(Date.new(2026, 8, 15))).to eq(Date.new(2026, 9, 30))
      end

      it "clamps to February 28 in a non-leap year" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 31)

        expect(term.due_date_for(Date.new(2026, 1, 15))).to eq(Date.new(2026, 2, 28))
      end

      it "clamps to February 29 in a leap year" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 31)

        expect(term.due_date_for(Date.new(2028, 1, 15))).to eq(Date.new(2028, 2, 29))
      end

      context "with month_offset 0" do
        it "rolls forward to the next month when the day is before the issuing date" do
          term = described_class.from_h(term_type: "day_of_month", day_of_month: 10, month_offset: 0)

          expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 8, 10))
        end

        it "does not roll when the day equals the issuing date" do
          term = described_class.from_h(term_type: "day_of_month", day_of_month: 15, month_offset: 0)

          expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 15))
        end

        it "does not roll when the day is after the issuing date" do
          term = described_class.from_h(term_type: "day_of_month", day_of_month: 20, month_offset: 0)

          expect(term.due_date_for(issuing_date)).to eq(Date.new(2026, 7, 20))
        end

        it "re-clamps when the roll lands on a shorter month" do
          # issued Jan 31, day 30 → Jan 30 is in the past → roll → Feb 28
          term = described_class.from_h(term_type: "day_of_month", day_of_month: 30, month_offset: 0)

          expect(term.due_date_for(Date.new(2026, 1, 31))).to eq(Date.new(2026, 2, 28))
        end
      end
    end
  end
end
