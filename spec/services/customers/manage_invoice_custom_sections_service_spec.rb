# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::ManageInvoiceCustomSectionsService do
  let(:customer) { create(:customer) }
  let(:invoice_custom_sections) { create_list(:invoice_custom_section, 4, organization: customer.organization) }
  let(:skip_invoice_custom_sections) { nil }
  let(:service) { described_class.new(customer: customer, section_ids:, skip_invoice_custom_sections:) }
  let(:section_ids) { nil }

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

    context 'when sending skip_invoice_custom_sections: true AND selected_ids' do
      let(:skip_invoice_custom_sections) { true }
      let(:section_ids) { [1, 2,3 ] }

      it 'raises an error' do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.message).to include('skip_sections_and_selected_ids_sent_together')
      end
    end

    context 'when updating selected_invoice_custom_sections' do
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

        it 'still sets selected invoice_custom_sections as custom' do
          service.call
          expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(invoice_custom_sections[2..3].map(&:id))
          expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
        end
      end

      context 'when section_ids are totally custom' do
        let(:section_ids) { invoice_custom_sections[1..2].map(&:id) }

        it 'assigns customer sections' do
          service.call
          expect(customer.reload.selected_invoice_custom_sections.ids).to match_array(section_ids)
          expect(customer.applicable_invoice_custom_sections.ids).to match_array(section_ids)
        end
      end

      context 'when selected_ids are an empty array' do
        let(:section_ids) { [] }

        it 'assigns organization sections' do
          service.call
          expect(customer.reload.selected_invoice_custom_sections.ids).to match_array([])
          expect(customer.applicable_invoice_custom_sections.ids).to match_array(customer.organization.selected_invoice_custom_sections.ids)
        end
      end

      context 'when setting invoice_custom_sections_ids when previously customer had skip_invoice_custom_sections' do
        let(:section_ids) { [] }

        before { customer.update(skip_invoice_custom_sections: true) }

        it 'sets skip_invoice_custom_sections to false' do
          service.call
          expect(customer.reload.skip_invoice_custom_sections).to be_falsey
          expect(customer.selected_invoice_custom_sections.ids).to match_array([])
          expect(customer.applicable_invoice_custom_sections.ids).to match_array(customer.organization.selected_invoice_custom_sections.ids)
        end
      end
    end

    context 'when updating customer to skip_invoice_custom_sections' do
      let(:skip_invoice_custom_sections) { true }

      before { customer.selected_invoice_custom_sections << invoice_custom_sections[1] }

      it 'sets skip_invoice_custom_sections to true' do
        service.call
        expect(customer.reload.skip_invoice_custom_sections).to be_truthy
        expect(customer.selected_invoice_custom_sections).to be_empty
        expect(customer.applicable_invoice_custom_sections).to be_empty
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
