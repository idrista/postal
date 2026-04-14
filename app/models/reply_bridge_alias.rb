# frozen_string_literal: true

class ReplyBridgeAlias < ApplicationRecord

  belongs_to :server

  validates :email, presence: true, format: { with: /@/ }, uniqueness: { scope: :server_id, case_sensitive: false }
  validates :token, presence: true, uniqueness: true

  before_validation :normalize_email
  before_validation :ensure_token
  before_validation :ensure_expiry

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def address
    "reply+#{token}@#{server.reply_bridge_domain}"
  end

  def touch_used!
    update_columns(last_used_at: Time.current, expires_at: default_expiry)
  end

  private

  def normalize_email
    self.email = Postal::Helpers.strip_name_from_address(email).to_s.downcase.presence
  end

  def ensure_token
    self.token ||= SecureRandom.alphanumeric(16).downcase
  end

  def ensure_expiry
    self.expires_at ||= default_expiry
  end

  def default_expiry
    server.reply_bridge_alias_ttl_days.to_i.days.from_now
  end

end
