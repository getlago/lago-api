# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe Utils::PdfAttachmentService do
  subject(:result) { described_class.call(file:, attachment_content:, attachment_name:) }

  let(:file) do
    Tempfile.new(["test", ".pdf"]).tap do |tempfile|
      tempfile.binmode
      tempfile.write(File.binread(Rails.root.join("spec/fixtures/blank.pdf")))
      tempfile.flush
    end
  end
  let(:attachment_content) { "<xml>content</xml>" }
  let(:attachment_name) { "factur-x.xml" }
  let(:attachments_output) { Open3.capture3("pdfcpu", "attachments", "list", file.path).first }

  after do
    file.close! if file.respond_to?(:close!)
  end

  describe "#call" do
    it "adds the named attachment to the PDF with the real binary" do
      expect(result).to be_success
      expect(result.file).to eq(file)
      expect(attachments_output).to include(attachment_name)
    end

    context "when file param is not a file" do
      let(:file) { "" }

      it "fails" do
        expect(result).to be_failure
        expect(result.error.message).to eq("file_not_found")
      end
    end

    context "when file param is not a pdf" do
      let(:file) { instance_double(File, path: "/tmp/test.doc") }

      before do
        allow(File).to receive(:file?).with(file).and_return(true)
      end

      it "fails" do
        expect(result).to be_failure
        expect(result.error.message).to eq("not_a_pdf_file")
      end
    end

    context "when pdfcpu fails" do
      before do
        allow(Kernel).to receive(:system)
          .with("pdfcpu", "attachments", "add", file.path, kind_of(String))
          .and_return(false)
      end

      it "fails" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end
  end
end
