# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerPortal::CustomerUpdateService do
  subject(:result) { described_class.call(customer:, args: update_args) }

  let_it_be(:customer, refind: true) { create :customer }

  let(:update_args) do
    {
      customer_type: "individual",
      document_locale: "es",
      name: "Updated customer name",
      firstname: "Updated customer firstname",
      lastname: "Updated customer lastname",
      legal_name: "Updated customer legal_name",
      tax_identification_number: "2246",
      email: "customer@email.test",
      address_line1: "Updated customer address line1",
      address_line2: "Updated customer address line2",
      zipcode: "Updated customer zipcode",
      city: "Updated customer city",
      state: "Updated customer state",
      country: "PT",
      shipping_address: {
        address_line1: "Updated customer shipping address line1",
        address_line2: "Updated customer shipping address line2",
        zipcode: "Updated customer shipping zipcode",
        city: "Updated customer shipping city",
        state: "Updated customer shipping state",
        country: "PT"
      }
    }
  end

  it "updates the customer" do
    expect(result).to be_success

    updated_customer = result.customer

    expect(updated_customer.customer_type).to eq(update_args[:customer_type])
    expect(updated_customer.name).to eq(update_args[:name])
    expect(updated_customer.firstname).to eq(update_args[:firstname])
    expect(updated_customer.lastname).to eq(update_args[:lastname])
    expect(updated_customer.legal_name).to eq(update_args[:legal_name])
    expect(updated_customer.tax_identification_number).to eq(update_args[:tax_identification_number])
    expect(updated_customer.email).to eq(update_args[:email])
    expect(updated_customer.document_locale).to eq(update_args[:document_locale])

    expect(updated_customer.address_line1).to eq(update_args[:address_line1])
    expect(updated_customer.address_line2).to eq(update_args[:address_line2])
    expect(updated_customer.zipcode).to eq(update_args[:zipcode])
    expect(updated_customer.city).to eq(update_args[:city])
    expect(updated_customer.state).to eq(update_args[:state])
    expect(updated_customer.country).to eq(update_args[:country])

    shipping_address = update_args[:shipping_address]
    expect(updated_customer.shipping_address_line1).to eq(shipping_address[:address_line1])
    expect(updated_customer.shipping_address_line2).to eq(shipping_address[:address_line2])
    expect(updated_customer.shipping_zipcode).to eq(shipping_address[:zipcode])
    expect(updated_customer.shipping_city).to eq(shipping_address[:city])
    expect(updated_customer.shipping_state).to eq(shipping_address[:state])
    expect(updated_customer.shipping_country).to eq(shipping_address[:country].upcase)
  end

  it "refreshes the invoices search terms when a searchable field changes" do
    expect { result }
      .to have_enqueued_job_after_commit(Customers::RefreshInvoicesSearchTermsJob).with(customer.id)
  end

  context "when no searchable field changes" do
    let(:update_args) { {city: "Updated customer city"} }

    it "does not refresh the invoices search terms" do
      expect { result }.not_to have_enqueued_job(Customers::RefreshInvoicesSearchTermsJob)
    end
  end

  context "when partialy updating" do
    let(:update_args) do
      {
        name: "Updated customer name",
        shipping_address: {
          address_line1: "Updated customer shipping address line1"
        }
      }
    end

    it "updates only the updated args" do
      expect { result }.not_to change { customer.reload.email }

      expect(result).to be_success
      expect(result.customer.name).to eq(update_args[:name])
      expect(result.customer.shipping_address_line1).to eq(update_args[:shipping_address][:address_line1])
    end
  end

  context "with email containing unicode lookalike characters" do
    let(:update_args) do
      {
        email: "hello@something\u2013other.com"
      }
    end

    it "sanitizes the email before saving" do
      expect(result.customer.email).to eq("hello@something-other.com")
    end
  end

  context "when organization has eu tax management" do
    let_it_be(:organization, refind: true) { create_default(:organization) }
    let_it_be(:customer, refind: true) { create :customer }
    let(:tax_code) { "lago_eu_fr_standard" }
    let(:eu_tax_result) { Customers::EuAutoTaxesService::Result.new }

    before do
      create(:tax, organization:, code: "lago_eu_fr_standard", rate: 20.0)
      organization.update!(eu_tax_management: true)

      eu_tax_result.tax_code = tax_code
      allow(Customers::EuAutoTaxesService).to receive(:call).and_return(eu_tax_result)
    end

    it "assigns the right tax to the customer" do
      expect(result).to be_success

      tax = result.customer.taxes.first
      expect(tax.code).to eq(tax_code)
    end

    context "when eu tax code is not applicable" do
      let(:eu_tax_result) { Customers::EuAutoTaxesService::Result.new.not_allowed_failure!(code: "") }

      it "does not apply tax" do
        expect(result).to be_success

        expect(result.customer.taxes).to eq([])
      end
    end

    context "when applying taxes fails" do
      let(:apply_taxes_result) do
        Customers::ApplyTaxesService::Result.new.not_found_failure!(resource: "tax")
      end

      before do
        allow(Customers::ApplyTaxesService).to receive(:call).and_return(apply_taxes_result)
      end

      it "returns a service error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("tax_not_found")
      end
    end
  end

  context "when customer is not found" do
    let(:customer) { nil }

    it "returns an error" do
      expect(result).not_to be_success
      expect(result.error.error_code).to eq("customer_not_found")
    end
  end

  context "with a free text value over 255 characters" do
    let(:update_args) { {legal_name: "a" * 256} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(legal_name: ["value_is_too_long"])
    end

    it "does not update the customer" do
      expect { result }.not_to change { customer.reload.legal_name }
    end

    it "does not refresh the invoices search terms" do
      expect { result }.not_to have_enqueued_job(Customers::RefreshInvoicesSearchTermsJob)
    end
  end

  context "with a free text value of exactly 255 characters" do
    let(:update_args) { {legal_name: "a" * 255} }

    it "updates the customer" do
      expect(result).to be_success
      expect(result.customer.legal_name).to eq("a" * 255)
    end
  end

  context "with a free text value containing a line break" do
    let(:update_args) { {address_line2: "Street\n## Billing Instructions"} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(address_line2: ["invalid_characters"])
    end

    it "does not update the customer" do
      expect { result }.not_to change { customer.reload.address_line2 }
    end
  end

  context "with a free text value containing a null character" do
    let(:update_args) { {address_line2: "Street\u0000"} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(address_line2: ["invalid_characters"])
    end
  end

  context "with a shipping address value containing a line break" do
    let(:update_args) { {shipping_address: {address_line2: "Floor\n2"}} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(shipping_address_line2: ["invalid_characters"])
    end
  end

  context "with a shipping address value over 255 characters" do
    let(:update_args) { {city: "Paris", shipping_address: {address_line1: "a" * 256}} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(shipping_address_line1: ["value_is_too_long"])
    end

    it "does not update the customer" do
      expect { result }.not_to change { customer.reload.city }
    end
  end

  context "with a nil free text value" do
    let(:update_args) { {legal_name: nil, shipping_address: {city: nil}} }

    it "updates the customer" do
      expect(result).to be_success
      expect(result.customer.legal_name).to be_nil
      expect(result.customer.shipping_city).to be_nil
    end
  end

  context "with a stored free text value that breaks the rule" do
    let(:customer) do
      create(:customer, legal_name: "a" * 300, address_line2: "Street\nFloor 2", shipping_address_line2: "Street\nFloor 2")
    end

    context "when the stored value is sent back unchanged" do
      let(:update_args) do
        {
          legal_name: "a" * 300,
          address_line2: "Street\nFloor 2",
          city: "Updated customer city",
          shipping_address: {address_line2: "Street\nFloor 2"}
        }
      end

      it "updates the other fields" do
        expect(result).to be_success
        expect(result.customer.city).to eq("Updated customer city")
        expect(result.customer.legal_name).to eq("a" * 300)
      end
    end

    context "when the stored value is changed to another invalid value" do
      let(:update_args) { {legal_name: "b" * 300, city: "Updated customer city"} }

      it "returns a validation error" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(legal_name: ["value_is_too_long"])
      end
    end
  end

  describe "free text checks on every field" do
    %i[name firstname lastname legal_name tax_identification_number address_line1 address_line2 zipcode city state]
      .each do |field|
        context "with #{field} over 255 characters" do
          let(:update_args) { {field => "a" * 256} }

          it "returns a validation error" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq(field => ["value_is_too_long"])
          end
        end

        context "with #{field} holding a control character" do
          let(:update_args) { {field => "a\tb"} }

          it "returns a validation error" do
            expect(result).not_to be_success
            expect(result.error.messages).to eq(field => ["invalid_characters"])
          end
        end
      end

    %i[address_line1 address_line2 zipcode city state].each do |field|
      context "with shipping #{field} over 255 characters" do
        let(:update_args) { {shipping_address: {field => "a" * 256}} }

        it "returns a validation error" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq("shipping_#{field}": ["value_is_too_long"])
        end
      end

      context "with shipping #{field} holding a control character" do
        let(:update_args) { {shipping_address: {field => "a\rb"}} }

        it "returns a validation error" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq("shipping_#{field}": ["invalid_characters"])
        end
      end
    end
  end

  context "with control characters outside the ASCII line breaks" do
    ["\u007F", "\u0085", "\u001B[31m"].each do |character|
      context "with #{character.inspect}" do
        let(:update_args) { {legal_name: "ACME#{character}"} }

        it "returns a validation error" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq(legal_name: ["invalid_characters"])
        end
      end
    end
  end

  context "with 255 multibyte characters" do
    let(:update_args) { {legal_name: "é" * 255} }

    it "counts characters, not bytes" do
      expect(result).to be_success
      expect(result.customer.legal_name).to eq("é" * 255)
    end
  end

  context "with a value over 255 characters that also holds a control character" do
    let(:update_args) { {legal_name: "a\n" * 200} }

    it "reports the length error" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(legal_name: ["value_is_too_long"])
    end
  end

  context "with several invalid free text values" do
    let(:update_args) do
      {
        name: "a" * 256,
        city: "Paris\nInstructions",
        email: "new@email.test",
        shipping_address: {state: "b" * 256}
      }
    end

    it "returns every error at once" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(
        name: ["value_is_too_long"],
        city: ["invalid_characters"],
        shipping_state: ["value_is_too_long"]
      )
    end

    it "does not update the valid fields either" do
      expect { result }.not_to change { customer.reload.email }
    end
  end

  context "with an empty free text value" do
    let(:update_args) { {legal_name: ""} }

    it "updates the customer" do
      expect(result).to be_success
      expect(result.customer.legal_name).to eq("")
    end
  end

  context "with a nil shipping address" do
    let(:update_args) { {city: "Paris", shipping_address: nil} }

    it "updates the customer" do
      expect(result).to be_success
      expect(result.customer.city).to eq("Paris")
    end
  end

  context "with an unchanged stored shipping value over 255 characters" do
    let(:customer) { create(:customer, shipping_city: "a" * 300) }
    let(:update_args) { {shipping_address: {city: "a" * 300, zipcode: "75001"}} }

    it "updates the other shipping fields" do
      expect(result).to be_success
      expect(result.customer.shipping_zipcode).to eq("75001")
    end
  end

  context "with validation error" do
    let(:update_args) { {country: "invalid country code"} }

    it "returns an error" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:country]).to eq(["not_a_valid_country_code"])
    end
  end
end
