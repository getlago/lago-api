# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataExports::ExportResourcesService, type: :service do
  subject(:result) { described_class.call(data_export:) }

  let(:data_export) { create :data_export, resource_type: 'invoices', format: 'csv' }
  let(:tempfile) { Tempfile.new("test_export") }

  before do
    allow(Tempfile).to receive(:create).and_yield(tempfile)
    allow(DataExports::Csv::Invoices).to receive(:call).and_return(nil)
  end

  describe '#call' do
    it 'updates the data export status to processing' do
      allow(data_export).to receive(:processing!)

      result
      expect(data_export).to have_received(:processing!)
    end

    it 'attaches the generated file to the data export' do
      result
      expect(data_export.file).to be_attached
    end

    it 'updates the data export status to completed' do
      allow(data_export).to receive(:completed!)

      result
      expect(data_export).to have_received(:completed!)
    end

    it 'sends a completion email' do
      expect { result }
        .to have_enqueued_mail(DataExportMailer, :completed)
        .with(params: {data_export:}, args: [])
    end

    it 'retunrs the data export result' do
      expect(result).to be_success

      aggregate_failures do
        expect(result.data_export).to be_completed
        expect(result.data_export.file).to be_present
      end
    end

    context 'when the data export is expired' do
      let(:data_export) { create(:data_export, expires_at: 1.hour.ago) }

      it 'returns a service failure result' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('data_export_expired')
        end
      end
    end

    context 'when the data export is already processed' do
      let(:data_export) { create(:data_export, :processing) }

      it 'returns a service failure result' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('data_export_processed')
        end
      end
    end

    context 'when an error occurs during processing' do
      before do
        allow(data_export)
          .to receive(:file)
          .and_raise(StandardError.new('error_message'))
      end

      it 'returns a service failure result' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('error_message')
          expect(data_export).to be_failed
        end
      end
    end

    context "when resource type is not supported" do
      let(:data_export) { create :data_export, resource_type: 'unknown' }

      it "returns a service failure result" do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq(
            "'unknown' resource not supported"
          )
          expect(data_export).to be_failed
        end
      end
    end

    context "when resource type is invoices" do
      let(:data_export) { create :data_export, resource_type: 'invoices', format: 'csv' }

      before do
        allow(DataExports::Csv::Invoices).to receive(:call).and_return(nil)
      end

      it "calls the Csv::Invoices exporter" do
        result

        expect(DataExports::Csv::Invoices)
          .to have_received(:call)
          .with(data_export:, output: tempfile)
      end
    end

    context "when resource type is invoice_fees" do
      let(:data_export) { create :data_export, resource_type: 'invoice_fees', format: 'csv' }

      before do
        allow(DataExports::Csv::InvoiceFees).to receive(:call).and_return(nil)
      end

      it "calls the Csv::InvoiceFees exporter" do
        result

        expect(DataExports::Csv::InvoiceFees)
          .to have_received(:call)
          .with(data_export:, output: tempfile)
      end
    end
  end
end
