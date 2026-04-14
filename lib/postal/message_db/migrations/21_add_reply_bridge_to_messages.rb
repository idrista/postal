# frozen_string_literal: true

module Postal
  module MessageDB
    module Migrations
      class AddReplyBridgeToMessages < Postal::MessageDB::Migration

        def up
          @database.query("ALTER TABLE `#{@database.database_name}`.`messages` " \
                          "ADD COLUMN `reply_bridge_requested` tinyint(1) DEFAULT 0, " \
                          "ADD COLUMN `reply_bridge_alias_id` int(11) DEFAULT NULL, " \
                          "ADD COLUMN `reply_bridge_error` varchar(255) DEFAULT NULL, " \
                          "ADD COLUMN `reply_bridge_source_message_id` int(11) DEFAULT NULL")
        end

      end
    end
  end
end
