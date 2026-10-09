# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::AssignService do
  subject(:result) { described_class.call(record:, params:) }

  let(:existing_term) { {"term_type" => "net", "days" => 30} }
  let(:record) { create(:customer, net_payment_term: 30, payment_term: existing_term) }

  describe "alias equivalence matrix" do
    context "when payment_term is not sent" do
      context "with net_payment_term N" do
        let(:params) { {net_payment_term: 45} }

        it "assigns the equivalent net term on both columns, without saving the record" do
          expect(result).to be_success

          expect(record.net_payment_term).to eq(45)
          expect(record.payment_term).to eq("term_type" => "net", "days" => 45)
          expect(record.reload.payment_term).to eq(existing_term)
        end
      end

      context "with net_payment_term null" do
        let(:params) { {net_payment_term: nil} }

        it "clears both columns" do
          result

          expect(record.net_payment_term).to be_nil
          expect(record.payment_term).to be_nil
        end
      end

      context "with net_payment_term absent" do
        let(:params) { {name: "Updated name"} }

        it "makes no change" do
          result

          expect(record.net_payment_term).to eq(30)
          expect(record.payment_term).to eq(existing_term)
        end
      end
    end

    context "when payment_term is sent" do
      context "with net_payment_term absent, payment_term object" do
        let(:params) { {payment_term: {term_type: "end_of_month"}} }

        it "assigns the term and mirrors a null alias for a non-net type" do
          result

          expect(record.payment_term).to eq("term_type" => "end_of_month")
          expect(record.net_payment_term).to be_nil
        end
      end

      context "with net_payment_term absent, payment_term null" do
        let(:params) { {payment_term: nil} }

        it "clears both columns" do
          result

          expect(record.payment_term).to be_nil
          expect(record.net_payment_term).to be_nil
        end
      end

      context "with net_payment_term N, payment_term equivalent object" do
        let(:params) { {net_payment_term: 45, payment_term: {term_type: "net", days: 45}} }

        it "assigns the term and mirrors the alias" do
          result

          expect(record.payment_term).to eq("term_type" => "net", "days" => 45)
          expect(record.net_payment_term).to eq(45)
        end
      end

      context "with net_payment_term N, payment_term different object" do
        let(:params) { {net_payment_term: 45, payment_term: {term_type: "end_of_month"}} }

        it "lets payment_term win, ignoring the sent alias" do
          result

          expect(record.payment_term).to eq("term_type" => "end_of_month")
          expect(record.net_payment_term).to be_nil
        end
      end

      context "with net_payment_term null, payment_term object (echo-back)" do
        let(:params) { {net_payment_term: nil, payment_term: {term_type: "net", days: 45}} }

        it "lets payment_term win and mirrors its alias" do
          result

          expect(record.payment_term).to eq("term_type" => "net", "days" => 45)
          expect(record.net_payment_term).to eq(45)
        end
      end

      context "with net_payment_term null, payment_term null" do
        let(:params) { {net_payment_term: nil, payment_term: nil} }

        it "clears both columns" do
          result

          expect(record.payment_term).to be_nil
          expect(record.net_payment_term).to be_nil
        end
      end

      context "with net_payment_term N, payment_term null" do
        let(:params) { {net_payment_term: 45, payment_term: nil} }

        it "lets payment_term win and clears both columns" do
          result

          expect(record.payment_term).to be_nil
          expect(record.net_payment_term).to be_nil
        end
      end

      context "with a due_on_receipt term" do
        let(:params) { {payment_term: {term_type: "due_on_receipt"}} }

        it "mirrors a zero alias" do
          result

          expect(record.payment_term).to eq("term_type" => "due_on_receipt")
          expect(record.net_payment_term).to eq(0)
        end
      end
    end
  end

  context "when net_payment_term is zero" do
    let(:params) { {net_payment_term: 0} }

    it "assigns a net term of zero rather than due_on_receipt" do
      result

      expect(record.payment_term).to eq("term_type" => "net", "days" => 0)
      expect(record.net_payment_term).to eq(0)
    end
  end

  context "when the record is a billing entity" do
    let(:record) { create(:billing_entity, net_payment_term: 30) }
    let(:params) { {payment_term: {term_type: "day_of_month", day_of_month: 15}} }

    it "assigns the term with its defaults and a null alias" do
      result

      expect(record.payment_term).to eq("term_type" => "day_of_month", "day_of_month" => 15, "month_offset" => 1)
      expect(record.net_payment_term).to be_nil
    end
  end
end
