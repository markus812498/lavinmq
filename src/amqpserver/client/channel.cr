module AMQPServer
  class Client
    class Channel
      def initialize(@state : Server::State)
      end

      def start_publish(exchange_name : String, routing_key : String)
        @next_publish_exchange_name = exchange_name
        @next_publish_routing_key = routing_key
      end

      def next_msg_headers(size, props)
        @next_msg = Message.new(@next_publish_exchange_name.not_nil!, @next_publish_routing_key.not_nil!, size, props)
      end

      def add_content(bytes)
        msg = @next_msg
        raise "No msg to write to" if msg.nil?
        msg.add_content bytes
        send_msg_to_queue(msg) if msg.full?
      end

      private def send_msg_to_queue(msg)
        ex = @state.exchanges[msg.exchange_name]
        raise "Exchange not declared" if ex.nil?
        queues = ex.queues_matching(msg.routing_key)
        queues.each do |q|
          q.write_msg(msg)
        end
      end

      def get(queue_name, no_ack)
        q = @state.queues[queue_name]
        raise "Queue #{queue_name} does not exist" if q.nil?
        q.get
      end
    end
  end
end
