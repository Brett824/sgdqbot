require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'date'
require 'json'
require 'openssl'
require 'cinch'

class Run

	attr_accessor :time, :game, :runner, :estimate, :comments, :commentators, :prize

	def initialize(tr)

		@time = Time.strptime("#{tr.children[0].text} -06:00", "%m/%d/%Y %H:%M:%S %z")
		@game = tr.children[2].text
		@runner = tr.children[4].text
		@estimate = tr.children[6].text
		@comments = tr.children[10].text
		@commentators = tr.children[12].text
		@prize = tr.children[14].text

	end

	def time
		@time.strftime("%I:%M:%S %p EDT (%A)")
	end

	def time_obj
		@time
	end

	def to_s
		"#{@time.strftime("%A, %I:%M:%S %p EDT")}: #{@game} by #{@runner}"
	end

end

def get_runs

	uri = URI.parse("http://gamesdonequick.com/schedule")
	http = Net::HTTP.new(uri.host, uri.port)
	request = Net::HTTP::Get.new(uri.request_uri)
	request.add_field('User-Agent', 'Mozilla/5.0 (Windows NT 6.1; rv:28.0) Gecko/20100101 Firefox/28.0')
	response = http.request(request)

	if response.class != Net::HTTPOK

        puts "error #{response.code}"
        return nil
        
	end

	body = response.body
	doc = Nokogiri::HTML(body)
	runs = doc.css("tr:not(.day-split)")

	schedule = []
	runs.each do |run|

		schedule << Run.new(run)

	end

	return schedule

end

def get_current_and_next(schedule)

	now = Time.now
	current_run = nil
	next_run = nil
	schedule.each do |run|

		if run.time_obj > now
			next_run = run
			break
		end

		current_run = run

	end

	return [current_run, next_run]

end

def get_runs_by_runner(schedule, runner)

	return schedule.select { |r| r.runner.downcase.include? runner.downcase }

end

def get_runs_by_game(schedule, game)

	return schedule.select { |r| r.game.downcase.include? game.downcase }

end

def make_reply(results)

	replystring = ""
	results.each_with_index do |res, i|
		replystring += "#{i+1}. #{res}"
		if i != results.length - 1
			replystring += " | "
		end
	end

	return replystring

end

def sgdq(tokens)
	current_run, next_run = get_current_and_next($schedule)
	return "Currently: #{current_run.game} by #{current_run.runner} | Up Next: #{next_run.game} by #{next_run.runner} at #{next_run.time}"
end

def process_results(results)

	if results.length > 5
		return "More than 5 results, please be more specific."
	elsif results.length == 0
		return "No runs found."
	end
	return make_reply(results)

end

def whenrunner(tokens)
	process_results get_runs_by_runner($schedule, tokens[1..-1].join(" "))
end

def whengame(tokens)
	process_results get_runs_by_game($schedule, tokens[1..-1].join(" "))
end

$bot_commands = {".sgdq" => method(:sgdq),
                ".whenrunner" => method(:whenrunner),
                ".whengame" => method(:whengame)}


$schedule = nil

bot = Cinch::Bot.new do
  
  configure do |c|
    c.server = "irc.speedrunslive.com"
    c.channels = ["#502"]
    c.nick = "BreetBot"

    Thread.new do
    	loop do

    		puts "Updating schedule"
    		STDOUT.flush
    		temp = get_runs
    		if temp.nil?
    			next
    		end
    		$schedule = temp
    		sleep(60)

    	end
    end

  end

  on :message do |m|

	tokens = m.message.split(" ")

	if $bot_commands.has_key? tokens[0]
		m.reply $schedule.nil? ? "Error accessing SGDQ schedule." : $bot_commands[tokens[0]].call(tokens)
	end

  end

end

bot.start
