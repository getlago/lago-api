# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::OneOffService do
  subject(:validator) { described_class.new(result, quote_version:, scope:) }

  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }
  let(:quote) { create(:quote, organization:, order_type: :one_off) }
  let(:quote_version) { build(:quote_version, quote:, organization:, currency:, billing_items:) }
  let(:currency) { "EUR" }
  let(:add_on) { create(:add_on, organization:, amount_cents: 10_000) }
  let(:billing_items) { {"add_ons" => [add_on_item]} }
  let(:add_on_item) do
    {
      "id" => add_on.id,
      "local_id" => "row-1",
      "payload" => {
        "code" => add_on.code,
        "units" => 1,
        "unit_amount_cents" => 10_000,
        "from_datetime" => nil,
        "to_datetime" => nil,
        "tax_codes" => []
      },
      "overrides" => {}
    }
  end

  describe "#valid? at scope :update" do
    let(:scope) { :update }

    it "is valid for a well-formed add-on" do
      expect(validator).to be_valid
      expect(result.error).to be_nil
    end

    context "when billing_items is empty (incomplete draft)" do
      let(:billing_items) { {} }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when currency is absent" do
      let(:currency) { nil }

      it "is valid (presence deferred to approve)" do
        expect(validator).to be_valid
      end
    end

    context "when currency is not a valid ISO4217 code" do
      let(:currency) { "ABC" }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:currency]).to eq(["value_is_invalid"])
      end
    end

    context "when billing_items has an unexpected top-level key" do
      let(:billing_items) { {"addons" => [add_on_item]} }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      end
    end

    context "when billing_items is an empty array" do
      let(:billing_items) { [] }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      end
    end

    context "when billing_items is a blank string" do
      let(:billing_items) { "" }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      end
    end

    context "when the add-on id does not exist in the organization" do
      let(:add_on_item) { super().merge("id" => SecureRandom.uuid) }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/id"]).to eq(["add_on_not_found"])
      end
    end

    context "when the add-on is soft-deleted" do
      before { add_on.discard }

      it "is valid (soft-deleted add-ons resolve)" do
        expect(validator).to be_valid
      end
    end

    context "when units are present but not positive" do
      let(:add_on_item) { super().tap { |i| i["payload"]["units"] = 0 } }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/units"]).to eq(["value_is_invalid"])
      end
    end

    context "when units are absent" do
      let(:add_on_item) { super().tap { |i| i["payload"].delete("units") } }

      it "is valid (presence deferred to approve)" do
        expect(validator).to be_valid
      end
    end

    context "when the add-on id and units are absent" do
      let(:add_on_item) do
        {
          "local_id" => "row-1",
          "payload" => {},
          "overrides" => {}
        }
      end

      it "is valid (incomplete draft rows are allowed)" do
        expect(validator).to be_valid
      end
    end

    context "when the override unit amount is negative" do
      let(:add_on_item) { super().merge("overrides" => {"unit_amount_cents" => -1}) }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/unit_amount_cents"]).to eq(["value_is_invalid"])
      end
    end

    context "when only one datetime boundary is present" do
      let(:add_on_item) { super().tap { |i| i["payload"]["from_datetime"] = "2026-01-01T00:00:00Z" } }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/to_datetime"]).to eq(["dates_must_be_paired"])
      end
    end

    context "when from_datetime is after to_datetime" do
      let(:add_on_item) do
        super().tap do |i|
          i["payload"]["from_datetime"] = "2026-02-01T00:00:00Z"
          i["payload"]["to_datetime"] = "2026-01-01T00:00:00Z"
        end
      end

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/to_datetime"]).to eq(["from_after_to"])
      end
    end

    context "when a datetime is present but unparseable" do
      let(:add_on_item) do
        super().tap do |i|
          i["payload"]["from_datetime"] = "not-a-date"
          i["payload"]["to_datetime"] = "2026-01-01T00:00:00Z"
        end
      end

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/from_datetime"]).to eq(["value_is_invalid"])
      end
    end

    context "when a tax code does not resolve to an organization tax" do
      let(:add_on_item) { super().tap { |i| i["payload"]["tax_codes"] = ["nope"] } }

      it "is invalid" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/tax_codes"]).to eq(["tax_not_found"])
      end
    end

    context "when every tax code resolves" do
      let(:tax) { create(:tax, organization:, code: "vat_20") }
      let(:add_on_item) { super().tap { |i| i["payload"]["tax_codes"] = [tax.code] } }

      it "is valid" do
        expect(validator).to be_valid
      end
    end

    context "when tax_codes is a bare string instead of an array" do
      let(:tax) { create(:tax, organization:, code: "vat_20") }
      let(:add_on_item) { super().tap { |i| i["payload"]["tax_codes"] = tax.code } }

      it "coerces it to an array and is valid" do
        expect(validator).to be_valid
      end
    end

    context "when local_id is missing" do
      let(:add_on_item) {
        super().tap { |i|
          i.delete("local_id")
          i["payload"]["units"] = 0
        }
      }

      it "keys the error by array index" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/0/units"]).to eq(["value_is_invalid"])
      end
    end
  end

  describe "#valid? at scope :approve" do
    let(:scope) { :approve }

    it "is valid for a complete, well-formed payload" do
      expect(validator).to be_valid
      expect(result.error).to be_nil
    end

    context "when billing_items is empty and currency is absent" do
      let(:billing_items) { {} }
      let(:currency) { nil }

      it "requires currency and at least one add-on" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:currency]).to eq(["value_is_mandatory"])
        expect(result.error.messages[:add_ons]).to eq(["add_ons_required"])
      end
    end

    context "when an add-on id is missing" do
      let(:add_on_item) { super().tap { |i| i.delete("id") } }

      it "requires the id" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/id"]).to eq(["value_is_mandatory"])
      end
    end

    context "when units are missing" do
      let(:add_on_item) { super().tap { |i| i["payload"].delete("units") } }

      it "requires units" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/units"]).to eq(["value_is_mandatory"])
      end
    end

    context "when the unit amount cannot be resolved" do
      let(:add_on_item) { {"local_id" => "row-1", "payload" => {"units" => 1}, "overrides" => {}} }

      it "requires the unit amount" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/unit_amount_cents"]).to eq(["value_is_mandatory"])
      end
    end

    context "when the unit amount is not provided but the catalog has one" do
      let(:add_on_item) do
        super().tap do |i|
          i["overrides"] = {}
          i["payload"].delete("unit_amount_cents")
        end
      end

      it "falls back to the catalog amount and is valid" do
        expect(validator).to be_valid
      end
    end

    context "when the add-on id is invalid and unit amount cannot be resolved" do
      let(:add_on_item) do
        {
          "id" => SecureRandom.uuid,
          "local_id" => "row-1",
          "payload" => {"units" => 1},
          "overrides" => {}
        }
      end

      it "only reports the unresolved add-on id" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to eq(:"add_ons/row-1/id" => ["add_on_not_found"])
      end
    end
  end

  describe "#valid? robustness and batching" do
    let(:scope) { :update }

    context "when currency is lowercase" do
      let(:currency) { "eur" }

      it "is invalid (codes are matched case-sensitively)" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:currency]).to eq(["value_is_invalid"])
      end
    end

    context "when an add-on id is not a valid uuid" do
      let(:add_on_item) { super().merge("id" => "not-a-uuid") }

      it "reports add_on_not_found instead of raising" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:"add_ons/row-1/id"]).to eq(["add_on_not_found"])
      end
    end

    context "when add_ons is not an array" do
      let(:billing_items) { {"add_ons" => "foo"} }

      it "is invalid on shape" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      end
    end

    context "when billing_items has both an unexpected key and non-array add_ons" do
      let(:billing_items) { {"add_ons" => "foo", "extra" => 1} }

      it "reports the shape error only once" do
        expect(validator).not_to be_valid
        expect(result.error.messages[:billing_items]).to eq(["value_is_invalid"])
      end
    end

    context "when non-hash entries are interleaved with add-ons" do
      let(:billing_items) do
        {"add_ons" => [{"payload" => {"units" => 0}}, "garbage", {"payload" => {"units" => 0}}]}
      end

      it "keys per-item errors by their original array index" do
        expect(validator).not_to be_valid
        expect(result.error.messages).to have_key(:"add_ons/2/units")
      end
    end

    context "when an add-on payload is not a hash" do
      let(:add_on_item) { super().merge("payload" => "bad") }

      it "is invalid without raising" do
        valid = nil

        expect { valid = validator.valid? }.not_to raise_error
        expect(valid).to eq(false)
        expect(result.error.messages[:"add_ons/row-1/payload"]).to eq(["value_is_invalid"])
      end
    end

    context "when an add-on overrides is not a hash" do
      let(:add_on_item) do
        super().tap do |item|
          item["payload"]["unit_amount_cents"] = 1_500
          item["overrides"] = "bad"
        end
      end

      it "is invalid without raising" do
        valid = nil

        expect { valid = validator.valid? }.not_to raise_error
        expect(valid).to eq(false)
        expect(result.error.messages[:"add_ons/row-1/overrides"]).to eq(["value_is_invalid"])
      end
    end

    context "with several add-ons carrying tax codes" do
      let(:tax_a) { create(:tax, organization:, code: "vat_a") }
      let(:tax_b) { create(:tax, organization:, code: "vat_b") }
      let(:other_add_on) { create(:add_on, organization:, amount_cents: 5_000) }
      let(:billing_items) do
        {
          "add_ons" => [
            add_on_item.tap { |item| item["payload"]["tax_codes"] = [tax_a.code] },
            {
              "id" => other_add_on.id,
              "local_id" => "row-2",
              "payload" => {"units" => 1, "unit_amount_cents" => 5_000, "tax_codes" => [tax_b.code]},
              "overrides" => {}
            }
          ]
        }
      end

      it "is valid" do
        expect(validator).to be_valid
      end

      it "resolves all tax codes in a single query" do
        validator # build the subject (and its factory-created records) before counting

        tax_queries = 0
        counter = ->(*, payload) { tax_queries += 1 if payload[:sql].include?('FROM "taxes"') }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          validator.valid?
        end

        expect(tax_queries).to eq(1)
      end
    end
  end
end
