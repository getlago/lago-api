# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerm do
  subject(:term) { described_class.from_h(attributes) }

  let(:attributes) { {term_type: "net", days: 30} }
  let(:issuing_date) { Date.new(2026, 7, 15) }

  describe ".from_h" do
    context "with string keys" do
      let(:attributes) { {"term_type" => "net", "days" => 30} }

      it "builds the term" do
        expect(term).to have_attributes(term_type: "net", days: 30)
      end
    end

    context "with symbol keys" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: 15, month_offset: 2} }

      it "builds the term" do
        expect(term).to have_attributes(term_type: "day_of_month", day_of_month: 15, month_offset: 2)
      end
    end

    context "with integer strings" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: "15", month_offset: "2"} }

      it "casts them to integers" do
        expect(term).to have_attributes(day_of_month: 15, month_offset: 2)
      end
    end

    context "when day_of_month has no month_offset" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: 15} }

      it "defaults month_offset to 1" do
        expect(term.month_offset).to eq(1)
      end
    end

    context "when the caller later mutates the term_type string" do
      let(:attributes) { {"term_type" => term_type, "days" => 30} }
      let(:term_type) { +"net" }

      it "keeps its own frozen copy" do
        lookup = {term => :found}
        term_type.replace("end_of_month")

        expect(term.term_type).to eq("net")
        expect(term.term_type).to be_frozen
        expect(lookup[term]).to eq(:found)
      end
    end

    context "when the term type is unknown" do
      let(:attributes) { {term_type: "fortnightly"} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "unknown term_type: fortnightly")
      end
    end

    context "when days is missing" do
      let(:attributes) { {term_type: "net_end_of_month"} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "invalid days for net_end_of_month: nil")
      end
    end

    context "when days is not an integer" do
      let(:attributes) { {term_type: "net", days: "thirty"} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, 'invalid days for net: "thirty"')
      end
    end

    context "when days is negative" do
      let(:attributes) { {term_type: "net", days: -1} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "invalid days for net: -1")
      end
    end

    context "when day_of_month is missing" do
      let(:attributes) { {term_type: "day_of_month"} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "invalid day_of_month for day_of_month: nil")
      end
    end

    context "when day_of_month is out of range" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: 0} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "invalid day_of_month for day_of_month: 0")
      end
    end

    context "when month_offset is negative" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: 15, month_offset: -1} }

      it "raises an ArgumentError" do
        expect { term }.to raise_error(ArgumentError, "invalid month_offset for day_of_month: -1")
      end
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

    it "returns nil for a value the model validation rejects" do
      expect(described_class.from_net_payment_term(-5)).to be_nil
      expect(described_class.from_net_payment_term("30")).to be_nil
    end
  end

  describe "#to_h" do
    context "when due_on_receipt" do
      let(:attributes) { {term_type: "due_on_receipt"} }

      it "serializes the term type only" do
        expect(term.to_h).to eq("term_type" => "due_on_receipt")
      end
    end

    context "when net" do
      it "serializes the days" do
        expect(term.to_h).to eq("term_type" => "net", "days" => 30)
      end
    end

    context "when day_of_month" do
      let(:attributes) { {term_type: "day_of_month", day_of_month: 31} }

      it "serializes the day and the defaulted month_offset" do
        expect(term.to_h).to eq("term_type" => "day_of_month", "day_of_month" => 31, "month_offset" => 1)
      end
    end

    context "when fields not carried by the term type are given" do
      let(:attributes) { {term_type: "end_of_month", days: 5, day_of_month: 10, month_offset: 2} }

      it "drops them" do
        expect(term.to_h).to eq("term_type" => "end_of_month")
      end
    end

    context "when built from its own output" do
      let(:attributes) { {"term_type" => "days_end_of_month", "days" => 30} }

      it "round-trips" do
        expect(term.to_h).to eq(attributes)
      end
    end
  end

  describe "#==" do
    it "compares terms by value" do
      expect(described_class.from_h(term_type: "net", days: 30))
        .to eq(described_class.from_h("term_type" => "net", "days" => 30))
      expect(described_class.from_h(term_type: "net", days: 30))
        .not_to eq(described_class.from_h(term_type: "net", days: 15))
      expect(described_class.from_h(term_type: "due_on_receipt"))
        .not_to eq("term_type" => "due_on_receipt")
    end

    it "hashes equal terms identically for group_by" do
      terms = [described_class.from_h(term_type: "net", days: 30), described_class.from_h("term_type" => "net", "days" => 30)]

      expect(terms.group_by(&:itself).size).to eq(1)
    end
  end

  describe "#net_payment_term_alias" do
    subject(:net_payment_term_alias) { term.net_payment_term_alias }

    context "when net" do
      it { is_expected.to eq(30) }
    end

    context "when due_on_receipt" do
      let(:attributes) { {term_type: "due_on_receipt"} }

      it { is_expected.to eq(0) }
    end

    [
      {term_type: "end_of_month"},
      {term_type: "net_end_of_month", days: 30},
      {term_type: "days_end_of_month", days: 30},
      {term_type: "day_of_month", day_of_month: 15}
    ].each do |term_attributes|
      context "when #{term_attributes[:term_type]}" do
        let(:attributes) { term_attributes }

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#label" do
    it "renders a localized sentence for each term type" do
      expect(described_class.from_h(term_type: "due_on_receipt").label).to eq("Due on receipt")
      expect(described_class.from_h(term_type: "net", days: 1).label).to eq("Payment due within 1 day")
      expect(described_class.from_h(term_type: "net", days: 30).label).to eq("Payment due within 30 days")
      expect(described_class.from_h(term_type: "end_of_month").label).to eq("Due at end of month")
      expect(described_class.from_h(term_type: "net_end_of_month", days: 1).label).to eq("Due 1 day after end of month")
      expect(described_class.from_h(term_type: "net_end_of_month", days: 30).label).to eq("Due 30 days after end of month")
      expect(described_class.from_h(term_type: "days_end_of_month", days: 1).label).to eq("Due 1 day, end of month")
      expect(described_class.from_h(term_type: "days_end_of_month", days: 30).label).to eq("Due 30 days, end of month")
    end

    it "renders a net-0 term as due on receipt" do
      expect(described_class.from_h(term_type: "net", days: 0).label).to eq("Due on receipt")
    end

    it "renders the month_offset variants for day_of_month" do
      expect(described_class.from_h(term_type: "day_of_month", day_of_month: 15, month_offset: 0).label)
        .to eq("Due on the 15 of this month")
      expect(described_class.from_h(term_type: "day_of_month", day_of_month: 15).label)
        .to eq("Due on the 15 of the following month")
      expect(described_class.from_h(term_type: "day_of_month", day_of_month: 15, month_offset: 2).label)
        .to eq("Due on the 15, 2 months after invoice")
    end

    context "when an issuing date is given" do
      it "names the month the day_of_month due date falls in" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 10, month_offset: 0)

        expect(term.label(issuing_date: Date.new(2026, 7, 15))).to eq("Due on the 10 of the following month")
        expect(term.label(issuing_date: Date.new(2026, 7, 5))).to eq("Due on the 10 of this month")
      end

      it "names the day the due date is clamped to in a short month" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 31)

        expect(term.label(issuing_date: Date.new(2026, 1, 15))).to eq("Due on the 28 of the following month")
        expect(term.label(issuing_date: Date.new(2028, 1, 15))).to eq("Due on the 29 of the following month")
        expect(term.label(issuing_date: Date.new(2026, 7, 15))).to eq("Due on the 31 of the following month")
      end

      it "re-clamps the day when an offset-0 term rolls into a shorter month" do
        term = described_class.from_h(term_type: "day_of_month", day_of_month: 30, month_offset: 0)

        expect(term.due_date_for(Date.new(2027, 1, 31))).to eq(Date.new(2027, 2, 28))
        expect(term.label(issuing_date: Date.new(2027, 1, 31))).to eq("Due on the 28 of the following month")
      end
    end

    it "renders in the current locale" do
      I18n.with_locale(:fr) do
        expect(described_class.from_h(term_type: "end_of_month").label).to eq("Payable fin de mois")
      end
    end
  end

  describe "#due_date_for" do
    subject(:due_date) { term.due_date_for(date) }

    let(:date) { issuing_date }

    context "when due_on_receipt" do
      let(:attributes) { {term_type: "due_on_receipt"} }

      it "returns the issuing date" do
        expect(due_date).to eq(Date.new(2026, 7, 15))
      end
    end

    context "when the issuing date is a Time" do
      let(:date) { Time.zone.parse("2026-07-15 10:30:00") }

      it "coerces to a Date so days are added as days, not seconds" do
        expect(due_date).to eq(Date.new(2026, 8, 14))
        expect(due_date).to be_a(Date)
      end
    end

    context "when net" do
      it "adds N days to the issuing date" do
        expect(due_date).to eq(Date.new(2026, 8, 14))
      end

      context "with 0 days" do
        let(:attributes) { {term_type: "net", days: 0} }

        it "equals due_on_receipt" do
          expect(due_date).to eq(issuing_date)
        end
      end
    end

    context "when end_of_month" do
      let(:attributes) { {term_type: "end_of_month"} }

      it "returns the last day of the issuing month" do
        expect(due_date).to eq(Date.new(2026, 7, 31))
      end

      context "when issued in February of a leap year" do
        let(:date) { Date.new(2028, 2, 10) }

        it "returns February 29" do
          expect(due_date).to eq(Date.new(2028, 2, 29))
        end
      end
    end

    context "when net_end_of_month (US)" do
      let(:attributes) { {term_type: "net_end_of_month", days: 30} }

      it "goes to end of month, then adds N days" do
        expect(due_date).to eq(Date.new(2026, 8, 30))
      end

      context "with 0 days" do
        let(:attributes) { {term_type: "net_end_of_month", days: 0} }

        it "equals end_of_month" do
          expect(due_date).to eq(Date.new(2026, 7, 31))
        end
      end
    end

    context "when days_end_of_month (EU)" do
      let(:attributes) { {term_type: "days_end_of_month", days: 30} }

      it "adds N days, then goes to end of month" do
        expect(due_date).to eq(Date.new(2026, 8, 31))
      end

      context "with 0 days" do
        let(:attributes) { {term_type: "days_end_of_month", days: 0} }

        it "equals end_of_month" do
          expect(due_date).to eq(Date.new(2026, 7, 31))
        end
      end
    end

    context "when day_of_month" do
      let(:attributes) { {term_type: "day_of_month", day_of_month:, month_offset:} }
      let(:day_of_month) { 15 }
      let(:month_offset) { nil }

      it "returns the Dth day of the month after month_offset" do
        expect(due_date).to eq(Date.new(2026, 8, 15))
      end

      context "with a month_offset greater than 1" do
        let(:month_offset) { 2 }

        it "skips that many months" do
          expect(due_date).to eq(Date.new(2026, 9, 15))
        end
      end

      context "when the day does not exist in the due month" do
        let(:day_of_month) { 31 }
        let(:date) { Date.new(2026, 8, 15) }

        it "clamps to the last day of the month" do
          expect(due_date).to eq(Date.new(2026, 9, 30))
        end
      end

      context "when the due month is February of a non-leap year" do
        let(:day_of_month) { 31 }
        let(:date) { Date.new(2026, 1, 15) }

        it "clamps to February 28" do
          expect(due_date).to eq(Date.new(2026, 2, 28))
        end
      end

      context "when the due month is February of a leap year" do
        let(:day_of_month) { 31 }
        let(:date) { Date.new(2028, 1, 15) }

        it "clamps to February 29" do
          expect(due_date).to eq(Date.new(2028, 2, 29))
        end
      end

      context "with month_offset 0" do
        let(:month_offset) { 0 }

        context "when the day is before the issuing date" do
          let(:day_of_month) { 10 }

          it "rolls forward to the next month" do
            expect(due_date).to eq(Date.new(2026, 8, 10))
          end
        end

        context "when the day equals the issuing date" do
          it "does not roll" do
            expect(due_date).to eq(Date.new(2026, 7, 15))
          end
        end

        context "when the day is after the issuing date" do
          let(:day_of_month) { 20 }

          it "does not roll" do
            expect(due_date).to eq(Date.new(2026, 7, 20))
          end
        end

        context "when the roll lands on a shorter month" do
          let(:day_of_month) { 30 }
          let(:date) { Date.new(2026, 1, 31) }

          it "re-clamps" do
            expect(due_date).to eq(Date.new(2026, 2, 28))
          end
        end
      end
    end
  end
end
