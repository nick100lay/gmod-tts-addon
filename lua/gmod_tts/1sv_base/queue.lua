

local queue_mt = {}
queue_mt.__index = queue_mt
gmod_tts.queue_mt = queue_mt

function gmod_tts.make_queue()
    queue = setmetatable({}, queue_mt)
    queue.size = 0
    return queue
end

function queue_mt:enqueue(text, voice, language, options)
    local node = { text = text, voice = voice, language = language, options = options or {} }
    if not self.head then
        self.tail = node 
        self.head = node
    else
        self.tail.next = node
        self.tail = node
    end
    self.size = self.size + 1
end

function queue_mt:dequeue()
    local prev_head = self.head
    self.head = self.head.next
    if not self.head then
        self.tail = nil
    end
    self.size = self.size - 1
    return prev_head.text, prev_head.voice, prev_head.language, prev_head.options
end

function queue_mt:clear()
    self.head = nil 
    self.tail = nil
    self.size = 0
end