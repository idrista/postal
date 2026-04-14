# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReplyBridge do
  let(:server) do
    create(:server,
           reply_bridge_mode: "AutoExternal",
           reply_bridge_domain: "reply.example.com",
           reply_bridge_sender: "reply@example.com",
           reply_bridge_sender_status: "OK",
           reply_bridge_mx_status: "OK")
  end

  before do
    create(:domain, :dns_all_ok, owner: server, name: "example.com", verified_at: Time.current)
  end

  describe ".prepare_outgoing" do
    it "replaces an external Reply-To with a bridge alias" do
      mail = Mail.new
      mail.from = "sender@example.com"
      mail.to = "student@example.net"
      mail.reply_to = "prof@gmail.com"
      mail.subject = "Lesson"
      mail.body = "Hello"

      result = described_class.prepare_outgoing(server, mail.to_s)

      parsed = Mail.new(result.raw_message)
      expect(result).to be_bridged
      expect(result.bridge_alias.email).to eq "prof@gmail.com"
      expect(parsed.reply_to).to eq [result.bridge_alias.address]
    end

    it "returns an error when the bridge is required but not configured" do
      server.update!(reply_bridge_mx_status: nil)
      mail = Mail.new(from: "sender@example.com", to: "student@example.net", reply_to: "prof@gmail.com", body: "Hello")

      result = described_class.prepare_outgoing(server, mail.to_s)

      expect(result).to be_required
      expect(result.error).to eq "Reply Bridge MX records are not ready."
    end
  end

  describe ".reemit_reply" do
    it "creates a clean outgoing message back to the alias email" do
      alias_record = described_class.alias_for(server, "prof@gmail.com")
      incoming = MessageFactory.incoming(server) do |message, mail|
        message.rcpt_to = alias_record.address
        message.reply_bridge_alias_id = alias_record.id
        mail.from = "student@example.net"
        mail.to = alias_record.address
      end

      outgoing = described_class.reemit_reply(incoming, alias_record)

      parsed = Mail.new(outgoing.raw_message)
      expect(outgoing.scope).to eq "outgoing"
      expect(outgoing.rcpt_to).to eq "prof@gmail.com"
      expect(parsed.from).to eq ["reply@example.com"]
      expect(parsed.reply_to.first).to match(/\Areply\+[a-z0-9]+@reply\.example\.com\z/)
    end

    it "reuses an existing alias for the reply sender" do
      alias_record = described_class.alias_for(server, "prof@gmail.com")
      reply_alias = described_class.alias_for(server, "student@example.net")
      incoming = MessageFactory.incoming(server) do |message, mail|
        message.rcpt_to = alias_record.address
        message.reply_bridge_alias_id = alias_record.id
        mail.from = "student@example.net"
        mail.to = alias_record.address
      end

      expect { described_class.reemit_reply(incoming, alias_record) }
        .not_to change { ReplyBridgeAlias.where(server: server, email: "student@example.net").count }
      expect(ReplyBridgeAlias.find_by(server: server, email: "student@example.net")).to eq reply_alias
    end
  end
end
