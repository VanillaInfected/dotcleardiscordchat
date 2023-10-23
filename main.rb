require 'discordrb'
require 'dotenv/load'
require 'logger'
require 'json'
require 'fileutils'
require 'rufus-scheduler'  # Добавлен гем rufus-scheduler

logger = Logger.new('bot.log')
logger.level = Logger::DEBUG

ALLOWED_USERS = ENV['ALLOWED_USERS'].split(',')

# Функция для загрузки настроек
def load_settings
  begin
    settings_data = File.read('settings')
    settings_data.split("\n").map { |line| line.split(' ') }.to_h
  rescue Errno::ENOENT
    {}
  end
end

# Функция для сохранения настроек
def save_settings(settings)
  File.write('settings', settings.map { |key, value| "#{key} #{value}" }.join("\n"))
end

# Функция для загрузки истории
def load_history
  begin
    history_data = File.read('history')
    history_data.split("\n").map { |line| JSON.parse(line) }
  rescue Errno::ENOENT
    []
  end
end

# Функция для сохранения истории
def save_history(history, channel_name)
  history_file = File.join('deleted_messages', "#{channel_name}_#{Time.now.strftime('%Y-%m-%d')}.log")
  FileUtils.mkdir_p('deleted_messages')
  File.write(history_file, history.map { |entry| JSON.dump(entry) }.join("\n"))
end

history = load_history
channel_settings = load_settings

# Инициализация планировщика
scheduler = Rufus::Scheduler.new

bot = Discordrb::Commands::CommandBot.new(
  token: ENV['DISCORD_BOT_TOKEN'],
  prefix: '!',
  log: logger
)

# Обработчик команды !setup
bot.command(:setup, min_args: 2, max_args: 2) do |event, channel_id, interval_minutes|
  logger.info("Команда !setup выполнена пользователем #{event.user.username} в канале #{event.channel.name}")

  # Проверка, разрешен ли пользователь для выполнения команды
  unless ALLOWED_USERS.empty? || ALLOWED_USERS.include?(event.user.id.to_s)
    logger.error("Пользователь #{event.user.username} не имеет разрешения на выполнение команды !setup.")
    return "У вас нет разрешения на выполнение этой команды."
  end

  channel = event.bot.channel(channel_id)
  interval_minutes = interval_minutes.to_i

  if channel && interval_minutes
    history << { timestamp: Time.now.to_s, author: event.user.username, content: "!setup #{channel_id} #{interval_minutes}", channel: channel.name, message_id: event.message.id }
    save_history(history, channel.name)

    channel_settings[channel.id] = interval_minutes
    save_settings(channel_settings)
    logger.info("Настройки для канала #{channel.name} сохранены. Сообщения будут удаляться каждые #{interval_minutes} минут.")
    "Настройки для канала #{channel.mention} сохранены. Сообщения будут удаляться каждые #{interval_minutes} минут."
  else
    logger.error("Не удалось найти указанный канал или значение интервала не является числом.")
    "Не удалось найти указанный канал или значение интервала не является числом."
  end
end

# Обработчик удаления сообщений
bot.message_delete do |event|
  channel_name = event.channel.name

  # Проверяем, есть ли у события объект сообщения
  if event.message
    deleted_message = event.message
  else
    # Если объект сообщения отсутствует, используем event.id для получения информации
    deleted_message = "Message with ID: #{event.id} (no message object)"
  end

  history << { timestamp: Time.now.to_s, author: event.user.username, content: deleted_message }
  save_history(history, channel_name)

  logger.info("Бот увидел новое сообщение, готов удалить через #{channel_settings[event.channel.id]} минут: #{deleted_message}")

  # Используем планировщик для удаления сообщения
  scheduler.at(event.timestamp + channel_settings[event.channel.id] * 60) do
    event.message.delete
    logger.info("Сообщение удалено: #{deleted_message}")
  end
end

bot.message do |event|
  if channel_settings.key?(event.channel.id)
    interval_minutes = channel_settings[event.channel.id]
    timestamp_cutoff = event.timestamp + interval_minutes * 60

    # Используем планировщик для удаления сообщения
    scheduler.at(event.timestamp + interval_minutes * 60) do
      event.message.delete
      logger.info("Сообщение удалено после #{interval_minutes} минут: #{event.message.content}")
    end
  end
end

bot.run