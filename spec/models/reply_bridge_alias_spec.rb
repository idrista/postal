# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReplyBridgeAlias do
  let(:server) { create(:server, reply_bridge_domain: "reply.example.com") }

  it "normalizes e-mail addresses" do
    alias_record = described_class.create!(server: server, email: "Person <User@Example.COM>")

    expect(alias_record.email).to eq "user@example.com"
  end

  it "builds an address for the server reply bridge domain" do
    alias_record = described_class.create!(server: server, email: "user@example.com")

    expect(alias_record.address).to eq "reply+#{alias_record.token}@reply.example.com"
  end
end
