# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveStorage::Service::Configurator do
  # `#resolve` rescues LoadError and re-raises it as `Missing service adapter for "GCS"`,
  # so a gem missing from the bundle anywhere in an adapter's require chain stays invisible
  # until a boot actually selects that adapter. Nothing else in dev or test loads these
  # adapters, since both storage gems are declared with `require: false`.
  it "can load the GCS adapter" do
    expect { require "active_storage/service/gcs_service" }.not_to raise_error
  end

  it "can load the S3 adapter" do
    expect { require "active_storage/service/s3_service" }.not_to raise_error
  end
end
