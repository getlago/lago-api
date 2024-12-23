# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateInvoiceCustomSectionsService do
  let(:customer) { create(:customer) }
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization: customer.organization) }
  let(:service) { described_class.new(customer: customer, section_ids:) }
  let(:section_ids) { [] }

  before do
    customer.selected_invoice_custom_sections << invoice_custom_sections[0] if customer
    customer.organization.selected_invoice_custom_sections = invoice_custom_sections[2..3] if customer
  end

  describe '#call' do
    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns not found failure' do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq('customer_not_found')
      end
    end

    context 'when section_ids match customer\'s applicable sections' do
      let(:section_ids) { [invoice_custom_sections.first.id] }

      it 'returns the result without changes' do
        result = service.call
        expect(result).to be_success
        expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
      end
    end

    context 'when section_ids match organization\'s selected sections' do
      let(:section_ids) { invoice_custom_sections[2..3].map(&:id) }

      it 'assigns organization sections to customer' do
        service.call
        expect(customer.reload.selected_invoice_custom_sections.ids).to match_array([])
        expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
      end
    end

    context 'when section_ids need to be assigned to customer' do
      let(:section_ids) { invoice_custom_sections[1..2].map(&:id) }

      it 'assigns customer sections' do
        service.call
        expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(section_ids)
      end
    end

    context 'when an ActiveRecord::RecordInvalid error is raised' do
      before do
        allow(customer).to receive(:selected_invoice_custom_sections=).and_raise(ActiveRecord::RecordInvalid.new(customer))
      end

      it 'returns record validation failure' do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
