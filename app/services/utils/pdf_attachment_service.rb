# frozen_string_literal: true

require "tmpdir"

module Utils
  class PdfAttachmentService < BaseService
    Result = BaseResult[:file]

    def initialize(file:, attachment_content:, attachment_name:)
      @file = file
      @attachment_content = attachment_content
      @attachment_name = attachment_name

      super
    end

    def call
      return result.not_found_failure!(resource: "file") unless File.file?(file)
      return result.not_allowed_failure!(code: "not_a_pdf_file") unless file.path.downcase.ends_with?(".pdf")

      success = attach_file

      if success
        result.file = file
      else
        result.third_party_failure!(third_party: "pdfcpu", error_code: "failed", error_message: "")
      end

      result
    end

    private

    attr_reader :file, :attachment_content, :attachment_name

    def attach_file
      Dir.mktmpdir("pdf-attachment") do |directory|
        attachment_path = File.join(directory, attachment_name)
        File.write(attachment_path, attachment_content)

        Kernel.system("pdfcpu", "attachments", "add", file.path, attachment_path)
      end
    end
  end
end
