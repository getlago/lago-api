# frozen_string_literal: true

module Utils
  class DocumentAttachment
    # Upload before attaching: attach(io:) commits the attachment and uploads in after_commit,
    # so a worker stopped in between leaves an attachment without a file, which the re-run skips.
    def self.attach(attachment, path:, filename:, content_type:)
      blob = File.open(path) do |io|
        ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:)
      end

      attachment.attach(blob)
    end
  end
end
