# frozen_string_literal: true

# # IdempotencyRecord is a low-level model used for tracking idempotent operations.
#
# This class provides the database representation for idempotency tracking,
# but direct usage is discouraged. Instead, use the higher-level API provided
# by the IdempotencyService or similar interfaces that handle the complexities
# of idempotency implementation.
#
# For most use cases, you should interact with the idempotency system through
# these higher-level abstractions rather than manipulating IdempotencyRecord
# instances directly.
class IdempotencyRecord < ApplicationRecord
  belongs_to :resource, polymorphic: true, optional: true
end

# == Schema Information
#
# Table name: idempotency_records
#
#  id              :uuid             not null, primary key
#  idempotency_key :binary           not null
#  resource_type   :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  resource_id     :uuid
#
# Indexes
#
#  index_idempotency_records_on_idempotency_key                (idempotency_key) UNIQUE
#  index_idempotency_records_on_resource_type_and_resource_id  (resource_type,resource_id)
#
