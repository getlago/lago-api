# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::DocumentAttachment do
  describe ".attach" do
    subject(:attach) do
      described_class.attach(invoice.file, path:, filename: "#{invoice.number}.pdf", content_type: "application/pdf")
    end

    let(:invoice) { create(:invoice) }
    let(:path) { Rails.root.join("spec/fixtures/blank.pdf").to_s }

    it "uploads the file and attaches it" do
      attach

      file = invoice.reload.file
      expect(file.filename.to_s).to eq("#{invoice.number}.pdf")
      expect(file.content_type).to eq("application/pdf")
      expect(file.download).to eq(File.binread(path))
    end

    context "when the upload fails" do
      before { allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Sidekiq::Shutdown) }

      it "does not attach the file" do
        expect { attach }.to raise_error(Sidekiq::Shutdown)
        expect(invoice.reload.file).not_to be_attached
      end
    end
  end
end
