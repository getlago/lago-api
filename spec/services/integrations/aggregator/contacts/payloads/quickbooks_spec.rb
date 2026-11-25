# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Contacts::Payloads::Quickbooks do
  before_all do
    create_default(:organization)
  end

  let(:integration) { create(:quickbooks_integration) }
  let(:integration_customer) do
    create(:quickbooks_customer, customer:, integration:, external_customer_id: "58")
  end
  let(:payload) { described_class.new(integration:, customer:, integration_customer:) }

  let(:customer_type) { "company" }
  let(:customer_name) { "Acme Inc" }
  let(:legal_name) { "Acme Holdings LLC" }
  let(:firstname) { "Jane" }
  let(:lastname) { "Doe" }
  let(:customer) do
    create(
      :customer,
      external_id: "cust-ext-001",
      customer_type:,
      name: customer_name,
      legal_name:,
      firstname:,
      lastname:,
      email: "billing@acme.test, ops@acme.test",
      phone: "+1 555 0100, +1 555 0199",
      address_line1: "1 Billing St",
      address_line2: "Suite 2",
      city: "Billing City",
      state: "CA",
      zipcode: "94016",
      country: "US",
      shipping_address_line1: "9 Shipping Ave",
      shipping_address_line2: "Dock 4",
      shipping_city: "Shipping City",
      shipping_state: "NY",
      shipping_zipcode: "10001",
      shipping_country: "US"
    )
  end

  let(:mapped_fields) do
    {
      "DisplayName" => "Acme Inc",
      "CompanyName" => "Acme Holdings LLC",
      "GivenName" => "Jane",
      "FamilyName" => "Doe",
      "PrimaryEmailAddr" => {"Address" => "billing@acme.test"},
      "PrimaryPhone" => {"FreeFormNumber" => "+1 555 0100"},
      "BillAddr" => {
        "Line1" => "1 Billing St",
        "Line2" => "Suite 2",
        "City" => "Billing City",
        "CountrySubDivisionCode" => "CA",
        "PostalCode" => "94016",
        "Country" => "US"
      },
      "ShipAddr" => {
        "Line1" => "9 Shipping Ave",
        "Line2" => "Dock 4",
        "City" => "Shipping City",
        "CountrySubDivisionCode" => "NY",
        "PostalCode" => "10001",
        "Country" => "US"
      }
    }
  end

  describe "#create_body" do
    subject(:create_body) { payload.create_body }

    it "returns one object with Intuit field names and Notes" do
      expect(create_body).to eq(
        mapped_fields.merge("Notes" => "Lago customer: #{customer.id} (cust-ext-001)")
      )
    end

    it "does not send a currency" do
      expect(create_body).not_to have_key("CurrencyRef")
    end

    describe "DisplayName" do
      context "when name contains a colon, a tab or a newline" do
        let(:customer_name) { "Acme: EU\tWest\nOffice" }

        it "replaces them with a space" do
          expect(create_body["DisplayName"]).to eq("Acme EU West Office")
        end
      end

      context "when name is blank and firstname and lastname are longer than 500 characters together" do
        let(:customer_name) { nil }
        let(:firstname) { "f" * 255 }
        let(:lastname) { "n" * 255 }

        it "keeps the first 500" do
          expect(create_body["DisplayName"]).to eq("#{"f" * 255} #{"n" * 244}")
        end
      end

      context "when name is blank" do
        let(:customer_name) { "" }

        it "uses firstname and lastname" do
          expect(create_body["DisplayName"]).to eq("Jane Doe")
        end
      end

      context "when name and lastname are blank" do
        let(:customer_name) { nil }
        let(:lastname) { nil }

        it "uses the firstname alone" do
          expect(create_body["DisplayName"]).to eq("Jane")
        end
      end

      context "when name, firstname and lastname are blank" do
        let(:customer_name) { nil }
        let(:firstname) { nil }
        let(:lastname) { "" }

        it "uses the external id" do
          expect(create_body["DisplayName"]).to eq("cust-ext-001")
        end
      end
    end

    context "when names are longer than 100 characters" do
      let(:legal_name) { "l" * 150 }
      let(:firstname) { "f" * 150 }
      let(:lastname) { "n" * 150 }

      it "keeps the first 100 of CompanyName, GivenName and FamilyName" do
        expect(create_body).to include(
          "CompanyName" => "l" * 100,
          "GivenName" => "f" * 100,
          "FamilyName" => "n" * 100
        )
      end
    end

    describe "CompanyName" do
      context "when legal_name is blank for a company" do
        let(:legal_name) { nil }

        it "uses the name" do
          expect(create_body["CompanyName"]).to eq("Acme Inc")
        end
      end

      context "when legal_name is present for an individual" do
        let(:customer_type) { "individual" }

        it "uses the legal name" do
          expect(create_body["CompanyName"]).to eq("Acme Holdings LLC")
        end
      end

      context "when legal_name is blank for an individual" do
        let(:customer_type) { "individual" }
        let(:legal_name) { "" }

        it "leaves CompanyName out" do
          expect(create_body).not_to have_key("CompanyName")
        end
      end
    end

    context "when optional fields are blank" do
      let(:customer_type) { nil }
      let(:legal_name) { nil }
      let(:firstname) { "" }
      let(:lastname) { nil }
      let(:customer) do
        create(
          :customer,
          external_id: "cust-ext-002",
          customer_type:,
          name: "Solo",
          legal_name:,
          firstname:,
          lastname:,
          email: nil,
          phone: "",
          address_line1: nil,
          address_line2: "",
          city: nil,
          state: nil,
          zipcode: "",
          country: nil,
          shipping_address_line1: "",
          shipping_address_line2: nil,
          shipping_city: nil,
          shipping_state: "",
          shipping_zipcode: nil,
          shipping_country: nil
        )
      end

      it "leaves out blank fields and fully blank addresses" do
        expect(create_body).to eq(
          "DisplayName" => "Solo",
          "Notes" => "Lago customer: #{customer.id} (cust-ext-002)"
        )
      end
    end

    context "when only some address lines are filled" do
      let(:customer) do
        create(
          :customer,
          external_id: "cust-ext-003",
          name: "Partial",
          address_line1: nil,
          address_line2: nil,
          city: "Lyon",
          state: nil,
          zipcode: nil,
          country: "FR",
          shipping_address_line1: nil,
          shipping_address_line2: nil,
          shipping_city: nil,
          shipping_state: nil,
          shipping_zipcode: "69001",
          shipping_country: nil
        )
      end

      it "keeps only the filled lines of each address" do
        expect(create_body["BillAddr"]).to eq("City" => "Lyon", "Country" => "FR")
        expect(create_body["ShipAddr"]).to eq("PostalCode" => "69001")
      end
    end
  end

  describe "#update_body" do
    subject(:update_body) { payload.update_body }

    it "returns the mapped fields with Id and sparse, without Notes" do
      expect(update_body).to eq(mapped_fields.merge("Id" => "58", "sparse" => true))
    end

    it "does not send Notes, SyncToken or a currency" do
      expect(update_body.keys).not_to include("Notes", "SyncToken", "CurrencyRef")
    end

    context "when optional fields are blank" do
      let(:customer) do
        create(
          :customer,
          external_id: "cust-ext-002",
          customer_type: nil,
          name: "Solo",
          legal_name: nil,
          firstname: "",
          lastname: nil,
          email: nil,
          phone: "",
          address_line1: nil,
          address_line2: "",
          city: nil,
          state: nil,
          zipcode: "",
          country: nil,
          shipping_address_line1: "",
          shipping_address_line2: nil,
          shipping_city: nil,
          shipping_state: "",
          shipping_zipcode: nil,
          shipping_country: nil
        )
      end

      it "leaves out blank fields and fully blank addresses" do
        expect(update_body).to eq("DisplayName" => "Solo", "Id" => "58", "sparse" => true)
      end
    end
  end

  describe "#with_unique_display_name" do
    it "suffixes the display name of a create body with the external id" do
      body = payload.with_unique_display_name(payload.create_body)

      expect(body).to eq(payload.create_body.merge("DisplayName" => "Acme Inc (cust-ext-001)"))
    end

    it "suffixes the display name of an update body with the external id" do
      body = payload.with_unique_display_name(payload.update_body.merge("SyncToken" => "3"))

      expect(body["DisplayName"]).to eq("Acme Inc (cust-ext-001)")
      expect(body["SyncToken"]).to eq("3")
      expect(body["Id"]).to eq("58")
    end

    context "when the display name falls back to the external id" do
      let(:customer_name) { nil }
      let(:firstname) { nil }
      let(:lastname) { nil }

      it "returns nil, as the suffix would not make it unique" do
        expect(payload.with_unique_display_name(payload.create_body)).to be_nil
      end
    end

    context "when the name and the suffix are longer than 500 characters" do
      let(:customer_name) { "a" * 255 }

      before { customer.update!(external_id: "e" * 250) }

      it "shortens the name and keeps the whole suffix" do
        body = payload.with_unique_display_name(payload.create_body)

        expect(body["DisplayName"]).to eq("#{"a" * 247} (#{"e" * 250})")
        expect(body["DisplayName"].length).to eq(500)
      end
    end

    context "when the external id contains a colon" do
      before { customer.update!(external_id: "cust:001") }

      it "replaces it in the suffix" do
        expect(payload.with_unique_display_name(payload.create_body)["DisplayName"]).to eq("Acme Inc (cust 001)")
      end
    end
  end

  describe "#unique_display_name" do
    it "returns the suffixed name sent on a duplicate-name retry" do
      expect(payload.unique_display_name).to eq("Acme Inc (cust-ext-001)")
      expect(payload.with_unique_display_name(payload.create_body)["DisplayName"]).to eq(payload.unique_display_name)
    end
  end

  describe "#notes_marker" do
    it "holds the Lago customer id written in Notes" do
      expect(payload.notes_marker).to eq("Lago customer: #{customer.id}")
      expect(payload.create_body["Notes"]).to start_with(payload.notes_marker)
    end
  end
end
