require "socket"
require "./client/*"

module AMQPServer
  class Client
    def initialize(@socket : TCPSocket, @server_state : Server::State)
      @channels = Hash(UInt16, Client::Channel).new
      negotiate_client
    end

    def run_loop
      loop do
        frame = AMQP::Frame.decode @socket
        puts "=> #{frame.inspect}"
        case frame
        when AMQP::Channel::Open
          @channels[frame.channel] = Client::Channel.new(@server_state)
          send AMQP::Channel::OpenOk.new(frame.channel)
        when AMQP::Channel::Close
          @channels.delete frame.channel
          send AMQP::Channel::CloseOk.new(frame.channel)
        when AMQP::Exchange::Declare
          # change state
          send AMQP::Exchange::DeclareOk.new(frame.channel)
        when AMQP::Queue::Declare
          # change state
          send AMQP::Queue::DeclareOk.new(frame.channel, frame.queue_name, 0_u32, 0_u32)
        when AMQP::Connection::Close
          send AMQP::Connection::CloseOk.new
          break
        when AMQP::Basic::Publish
          @channels[frame.channel].start_publish(frame.exchange, frame.routing_key)
        when AMQP::Basic::Get
          msg = @channels[frame.channel].get(frame.queue, frame.no_ack)
          if msg
            send AMQP::Basic::GetOk.new(frame.channel, 1_u64, false, msg.exchange_name, msg.routing_key, 1_u32)
            send AMQP::HeaderFrame.new(frame.channel, 60_u16, 0_u16, msg.size, msg.properties)
            send AMQP::BodyFrame.new(frame.channel, msg.body.to_slice)
          else
            send AMQP::Basic::GetEmpty.new(frame.channel)
          end
        when AMQP::HeaderFrame
          @channels[frame.channel].next_msg_headers(frame.body_size, frame.properties)
        when AMQP::BodyFrame
          @channels[frame.channel].add_content(frame.body)
        end
      end
    ensure
      puts "Conn closed"
      @socket.close unless @socket.closed?
    end

    def send(frame : AMQP::Frame)
      puts "<= #{frame.inspect}"
      @socket.write frame.to_slice
    end

    private def negotiate_client
      start = Bytes.new(8)
      bytes = @socket.read_fully(start)

      if start != AMQP::PROTOCOL_START
        @socket.write AMQP::PROTOCOL_START
        @socket.close
        return
      end

      start = AMQP::Connection::Start.new
      send start
      start_ok = AMQP::Frame.decode @socket
      tune = AMQP::Connection::Tune.new(heartbeat: 0_u16)
      send tune
      tune_ok = AMQP::Frame.decode @socket
      open = AMQP::Frame.decode @socket
      open_ok = AMQP::Connection::OpenOk.new
      send open_ok
    end
  end
end
