# frozen_string_literal: true

# Stops the worker during the first storage upload, then runs the generator again.
# The host group defines `record` (the document) and `generate_document` (a lambda that runs the generator).
RSpec.shared_examples "an attachment uploaded before it is attached" do |attachment, webhook: nil|
  let(:storage) { ActiveStorage::Blob.service }

  before do
    upload_calls = 0
    allow(storage).to receive(:upload).and_wrap_original do |original, *args, **kwargs, &block|
      upload_calls += 1
      raise Sidekiq::Shutdown if upload_calls == 1

      original.call(*args, **kwargs, &block)
    end
  end

  it "leaves no attachment, so the re-run uploads and attaches the file" do
    expect { generate_document.call }.to raise_error(Sidekiq::Shutdown)
    expect(record.reload.public_send(attachment)).not_to be_attached

    if webhook
      expect { generate_document.call }.to have_enqueued_job(SendWebhookJob).with(webhook, record)
    else
      generate_document.call
    end

    expect(record.reload.public_send(attachment)).to be_attached
    expect(storage.exist?(record.public_send(attachment).key)).to be(true)
  end
end
