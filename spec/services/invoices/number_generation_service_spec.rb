# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::NumberGenerationService, type: :service do
  subject(:generation_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:organization) { create(:organization, document_numbering:) }
    let(:customer) { create(:customer, organization:, sequential_id: 1) }
    let(:document_numbering) { 'per_customer' }
    let(:status) { 'finalized' }
    let(:invoice) do
      create(:invoice, status:, organization:, customer:, sequential_id: nil, organization_sequential_id: 0)
    end

    context 'when invoice is draft' do
      let(:status) { 'draft' }

      it 'returns invoice with draft invoice number' do
        result = generation_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-DRAFT")
          expect(invoice.reload.sequential_id).to eq(nil)
          expect(invoice.reload.organization_sequential_id).to eq(0)
        end
      end
    end

    context 'when invoice is finalized and numbering is per_customer' do
      it 'generates sequential ID and invoice number' do
        result = generation_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-001-001")
          expect(invoice.reload.sequential_id).to eq(1)
          expect(invoice.reload.organization_sequential_id).to eq(0)
        end
      end

      context 'when sequential_id and organization_sequential_id are present' do
        before do
          invoice.sequential_id = 3
          invoice.organization_sequential_id = 5
        end

        it 'does not replace the sequential_id and organization_sequential_id' do
          result = generation_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-001-003")
            expect(invoice.reload.sequential_id).to eq(3)
            expect(invoice.reload.organization_sequential_id).to eq(5)
          end
        end
      end

      context 'when invoices already exist' do
        before do
          create(:invoice, customer:, organization:, sequential_id: 4, organization_sequential_id: 14)
          create(:invoice, customer:, organization:, sequential_id: 5, organization_sequential_id: 15)
        end

        it 'takes the next available id' do
          result = generation_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-001-006")
            expect(invoice.reload.sequential_id).to eq(6)
            expect(invoice.reload.organization_sequential_id).to eq(0)
          end
        end
      end

      context 'with invoices on other organization' do
        before do
          create(:invoice, sequential_id: 1, organization_sequential_id: 1)
        end

        it 'scopes the sequence to the organization' do
          result = generation_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-001-001")
            expect(invoice.reload.sequential_id).to eq(1)
            expect(invoice.reload.organization_sequential_id).to eq(0)
          end
        end
      end
    end

    context 'when invoice is finalized and numbering is per_organization' do
      let(:document_numbering) { 'per_organization' }

      it 'generates both sequential IDs and invoice number' do
        result = generation_service.call

        formatted_year_and_month = Time.now.in_time_zone(organization.timezone || 'UTC').strftime('%Y%m')
        aggregate_failures do
          expect(result).to be_success

          expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-#{formatted_year_and_month}-001")
          expect(invoice.reload.sequential_id).to eq(1)
          expect(invoice.reload.organization_sequential_id).to eq(1)
        end
      end

      context 'with organization numbering and invoices in another month' do
        let(:organization) { create(:organization, document_numbering: 'per_organization') }
        let(:created_at) { Time.now.utc - 1.month }

        before do
          create(:invoice, customer:, organization:, sequential_id: 4, organization_sequential_id: 14, created_at:)
          create(:invoice, customer:, organization:, sequential_id: 5, organization_sequential_id: 15, created_at:)
        end

        it 'scopes the organization_sequential_id to the organization' do
          result = generation_service.call

          formatted_year_and_month = Time.now.in_time_zone(organization.timezone || 'UTC').strftime('%Y%m')
          aggregate_failures do
            expect(result).to be_success

            expect(invoice.reload.number).to eq("#{organization.document_number_prefix}-#{formatted_year_and_month}-016")
            expect(invoice.reload.sequential_id).to eq(6)
            expect(invoice.reload.organization_sequential_id).to eq(16)
          end
        end
      end
    end
  end
end
