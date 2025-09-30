# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerSnapshots::CreateService do
  subject(:service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  describe "#call" do
    context "when invoice does not have a customer snapshot" do
      it "creates a customer snapshot with customer data" do
        result = service.call

        expect(result).to be_success
        expect(result.customer_snapshot).to be_a(CustomerSnapshot)
        expect(result.customer_snapshot.invoice).to eq(invoice)
        expect(result.customer_snapshot.organization).to eq(organization)
        expect(result.customer_snapshot.display_name).to eq(customer.display_name)
        expect(result.customer_snapshot.email).to eq(customer.email)
        expect(result.customer_snapshot.phone).to eq(customer.phone)
      end

      it "snapshots customer attributes" do
        customer.update!(
          name: "Test Customer",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: "+1234567890",
          url: "https://example.com",
          tax_identification_number: "12345",
          address_line1: "123 Main St",
          address_line2: "Apt 1",
          city: "Paris",
          state: "Ile-de-France",
          zipcode: "75001",
          country: "FR",
          legal_name: "John Doe Corp",
          legal_number: "123456789"
        )

        result = service.call

        expect(result).to be_success
        snapshot = result.customer_snapshot

        expect(snapshot.display_name).to eq(customer.display_name)
        expect(snapshot.firstname).to eq("John")
        expect(snapshot.lastname).to eq("Doe")
        expect(snapshot.email).to eq("john@example.com")
        expect(snapshot.phone).to eq("+1234567890")
        expect(snapshot.url).to eq("https://example.com")
        expect(snapshot.tax_identification_number).to eq("12345")
        expect(snapshot.applicable_timezone).to eq(customer.applicable_timezone)
        expect(snapshot.address_line1).to eq("123 Main St")
        expect(snapshot.address_line2).to eq("Apt 1")
        expect(snapshot.city).to eq("Paris")
        expect(snapshot.state).to eq("Ile-de-France")
        expect(snapshot.zipcode).to eq("75001")
        expect(snapshot.country).to eq("FR")
        expect(snapshot.legal_name).to eq("John Doe Corp")
        expect(snapshot.legal_number).to eq("123456789")
      end

      it "persists the customer snapshot" do
        expect { service.call }.to change(CustomerSnapshot, :count).by(1)
      end
    end

    context "when invoice already has a customer snapshot" do
      let(:existing_snapshot) { create(:customer_snapshot, invoice:, organization:, display_name: "Old Name") }

      before { existing_snapshot }

      it "returns success without creating a new snapshot" do
        result = service.call

        expect(result).to be_success
        expect(CustomerSnapshot.count).to eq(1)
        expect(result.customer_snapshot).to be_nil
      end

      context "when force is true" do
        subject(:service) { described_class.new(invoice:, force: true) }

        before do
          customer.update!(name: "Updated Name")
        end

        it "destroys the existing snapshot and creates a new one" do
          result = service.call

          expect(result).to be_success
          expect(CustomerSnapshot.count).to eq(1)
          expect(result.customer_snapshot).to be_present
          expect(result.customer_snapshot.id).not_to eq(existing_snapshot.id)
          expect(result.customer_snapshot.display_name).to eq(customer.display_name)
          expect(result.customer_snapshot.display_name).not_to eq("Old Name")
        end
      end
    end
  end
end
