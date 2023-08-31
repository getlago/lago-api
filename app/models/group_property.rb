# frozen_string_literal: true

class GroupProperty < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :charge
  belongs_to :group, -> { with_discarded }

  validates :values, presence: true
  validates :group_id, presence: true, uniqueness: { scope: :charge_id }

  default_scope -> { kept }
  scope :kept, -> { undiscarded.joins(:group).merge(Group.kept) }

  def kept?
    undiscarded? && group.kept?
  end
end
