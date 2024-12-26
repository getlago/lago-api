# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InvoiceCustomSectionsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'POST /api/v1/invoice_custom_sections' do
    subject { post_with_token(organization, '/api/v1/invoice_custom_sections', {invoice_custom_section: create_params}) }

    let(:create_params) do
      {
        name: 'custom section',
        code: 'section_1',
        description: 'description',
        details: 'details',
        display_name: 'display_name',
        selected: true
      }
    end

    it 'creates an invoice_custom_section' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_custom_section][:lago_id]).to be_present
      expect(json[:invoice_custom_section][:code]).to eq(create_params[:code])
      expect(json[:invoice_custom_section][:name]).to eq(create_params[:name])
      expect(json[:invoice_custom_section][:display_name]).to eq(create_params[:display_name])
      expect(json[:invoice_custom_section][:details]).to eq(create_params[:details])
      expect(json[:invoice_custom_section][:description]).to eq(create_params[:description])
      expect(json[:invoice_custom_section][:selected_for_organization]).to eq(true)

      expect(organization.reload.selected_invoice_custom_sections.count).to eq(1)
      expect(organization.reload.selected_invoice_custom_sections.ids).to eq([json[:invoice_custom_section][:lago_id]])
    end
  end

  describe 'PUT /api/v1/invoice_custom_sections/:code' do
    subject do
      put_with_token(organization, "/api/v1/invoice_custom_sections/#{ics_code}", {invoice_custom_section: update_params})
    end

    let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }
    let(:code) { 'ics_code' }
    let(:ics_code) { invoice_custom_section.code }
    let(:expiration_at) { Time.current + 15.days }
    let(:update_params) do
      {
        name: 'custom section',
        code: code,
        description: 'description',
        details: 'details',
        display_name: 'display_name',
        selected: true
      }
    end

    include_examples 'requires API permission', 'invoice_custom_section', 'write'

    it 'updates an invoice_custom_section' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_custom_section][:lago_id]).to eq(invoice_custom_section.id)
      expect(json[:invoice_custom_section][:code]).to eq(update_params[:code])
      expect(json[:invoice_custom_section][:description]).to eq(update_params[:description])
      expect(json[:invoice_custom_section][:details]).to eq(update_params[:details])
      expect(json[:invoice_custom_section][:display_name]).to eq(update_params[:display_name])
    end

    context 'when invoice_custom_section does not exist' do
      let(:ics_code) { SecureRandom.uuid }

      it 'returns not_found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoice_custom_section code already exists in organization scope (validation error)' do
      let!(:another_invoice_custom_section) { create(:invoice_custom_section, organization:) }
      let(:code) { another_invoice_custom_section.code }

      it 'returns unprocessable_entity error' do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when invoice_custom_section is updated to selected' do
      it 'adds the invoice_custom_section to the organization selected_invoice_custom_sections' do
        expect { subject }.to change(organization.reload.selected_invoice_custom_sections, :count).by(1)
      end
    end

    context 'when invoice_custom_section is updated to not selected' do
      let(:update_params) do
        {
          name: 'custom section',
          code: code,
          description: 'description',
          details: 'details',
          display_name: 'display_name',
          selected: false
        }
      end

      before do
        organization.selected_invoice_custom_sections << invoice_custom_section
      end

      it 'removes the invoice_custom_section to the organization selected_invoice_custom_sections' do
        expect { subject }.to change(organization.reload.selected_invoice_custom_sections, :count).by(-1)
      end
    end
  end

  describe 'GET /api/v1/invoice_custom_sections/:code' do
    subject { get_with_token(organization, "/api/v1/invoice_custom_sections/#{ics_code}") }

    let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }
    let(:ics_code) { invoice_custom_section.code }

    include_examples 'requires API permission', 'invoice_custom_section', 'read'

    it 'returns an invoice_custom_section' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_custom_section][:lago_id]).to eq(invoice_custom_section.id)
      expect(json[:invoice_custom_section][:code]).to eq(invoice_custom_section.code)
      expect(json[:invoice_custom_section][:selected_for_organization]).to eq(false)
    end

    context 'when invoice_custom_section does not exist' do
      let(:ics_code) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/invoice_custom_sections/:code' do
    subject { delete_with_token(organization, "/api/v1/invoice_custom_sections/#{ics_code}") }

    let!(:invoice_custom_section) { create(:invoice_custom_section, organization:) }
    let(:ics_code) { invoice_custom_section.code }

    include_examples 'requires API permission', 'invoice_custom_section', 'write'

    it 'deletes a invoice_custom_section' do
      expect { subject }.to change(InvoiceCustomSection, :count).by(-1)
    end

    it 'returns deleted invoice_custom_section' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_custom_section][:lago_id]).to eq(invoice_custom_section.id)
      expect(json[:invoice_custom_section][:code]).to eq(invoice_custom_section.code)
    end

    context 'when invoice_custom_section does not exist' do
      let(:ics_code) { SecureRandom.uuid }

      it 'returns not_found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/invoice_custom_sections' do
    subject { get_with_token(organization, '/api/v1/invoice_custom_sections', params) }

    let!(:invoice_custom_section) { create(:invoice_custom_section, organization:) }
    let(:params) { {} }

    include_examples 'requires API permission', 'invoice_custom_section', 'read'

    it 'returns invoice_custom_sections' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice_custom_sections].count).to eq(1)
      expect(json[:invoice_custom_sections].first[:lago_id]).to eq(invoice_custom_section.id)
      expect(json[:invoice_custom_sections].first[:code]).to eq(invoice_custom_section.code)
    end

    context 'with pagination' do
      let(:params) { {page: 1, per_page: 1} }

      before { create(:invoice_custom_section, organization:) }

      it 'returns invoice_custom_sections with correct meta data' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice_custom_sections].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
