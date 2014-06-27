require 'nokogiri'
require 'net/http'
require 'date'
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

  # TODO: break this connection stuff off into a seperate method
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

  # find the first run with time > now and the previous run had time < now.
  c,n = schedule.each_cons(2).find do |c,n|
    c.time_obj <= now && n.time_obj  > now
  end

  return nil, schedule[0] if now < schedule[0].time_obj
  return schedule[-1], nil if now >= schedule[-1].time_obj
  return c,n

end

def get_runs_by_runner(schedule, runner)

  schedule.select { |r| r.runner.downcase.include? runner.downcase }

end

def get_runs_by_game(schedule, game)

  schedule.select { |r| r.game.downcase.include? game.downcase }

end

# make a neat reply string from the result in the format of 1. {result} | 2. result | ... 
def make_reply(results)

  (1..results.length).zip(results).map{|i, res| "#{i}. #{res}"}.join(" | ")

end

def sgdq(_tokens)

  current_run, next_run = get_current_and_next($schedule)
  return "Currently: #{current_run.game} by #{current_run.runner} | Up Next: #{next_run.game} by #{next_run.runner} at #{next_run.time}"

end

# process the results of .when queries to check if they're valid
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

# dispatch table for different bot commands, generates reply strings in each of the methods
$bot_commands = {".sgdq" => method(:sgdq),
                ".whenrunner" => method(:whenrunner),
                ".whengame" => method(:whengame)}

$schedule = nil

bot = Cinch::Bot.new do
  
  configure do |c|

    if ARGV.length != 3 # this is just my default because it's where im using it right now
      c.server = "irc.speedrunslive.com"
      c.channels = ["#502"]
      c.nick = "BreetBot"
    else
      c.server = ARGV[0]
      c.channels = [ARGV[1]]
      c.nick = ARGV[2]
    end

    # spawn a new thread to keep up to date on the schedule by refreshing every 60 seconds (the schedule changes when things run short/long)
    Thread.new do
      loop do

        begin
          puts "Updating schedule"
          STDOUT.flush
          temp = get_runs
          if temp.nil?
            next
          end
          $schedule = temp
          sleep(60)
        rescue

        end
        
      end
    end

  end

  on :message do |m|

    tokens = m.message.split(" ")

    # check the dispatch table for the function, spit out an error message or build a reply string
    if $bot_commands.key? tokens[0]
      m.reply $schedule.nil? ? "Error accessing SGDQ schedule." : $bot_commands[tokens[0]].call(tokens)
    end

  end

end

bot.start
