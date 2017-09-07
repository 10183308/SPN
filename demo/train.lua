-- Usage: 
-- 1. write a dataset loader and put it in ./datasets/
-- 2. write your network model and put it in ./models/
-- 3. write your training scipt and put it in ./script
-- 4. execute "./script/your-script-file.sh"

require 'xlua'
require 'cuspn'

local utils = paths.dofile './utils.lua'

-- load options
local opt = utils.parseOpt{
    dataset = 'VOC',
    year = '2007',
    trainset = 'train',
    valset = 'val',
    testset = 'test',
    numClasses = 20,
    imageSize = 224,
    imageChannel = 3,
    savePath = 'logs/googleNetSoftProposal',
    datadir = './datasets/VOCdevkit/',
    logKeys = "{'note','epoch','elapse','remain','testLoss','testAcc','trainLoss','trainAcc'}",
    logFormats = "{'[%s]','%2d','%4.2f','%s','%4.6f','%2.4f','%4.6f','%2.4f'}",
    note = 'LeNet-5 on MNIST',
    maxEpoch = 5,
    batchSize = 16,
    checkpoint = 'better', -- 'all'/'better'/'none'/<number>
    enableSave = false,
    removeOldCheckpoints = false,
    model = 'googleNetSoftProposal', 
    onlyTest = false,
    trainMode = 'gpu',
    gpuDevice = '1',
    threadCount = 32,
    cudnnOptimize = true,
    optnetOptimize = true,
    evaluateEpoch = 1,
    -- optimize params
    optimMethod = 'sgd',
    learningRate = 0.01,
    learningRateDecay = 5e-7,
    weightDecay = 0.0005,
    dampening = 0,
    momentum = 0.9,
    -- decay learning rate
    epochStep = '25',
    learningRateDecayRatio = 0.5,
    notify = 'better', -- 'all'/'better'/'none'/
    -- custom params
    customParams = '{}'
}

-- torch configuration
torch.manualSeed(1)
torch.setdefaulttensortype('torch.FloatTensor')
if opt.trainMode == 'cpu' then
    torch.setnumthreads(opt.threadCount)
else
    require 'cutorch'
    if type(opt.gpuDevice) == 'table' then
        assert(table.getn(opt.gpuDevice) > 0, 'empty gpuDevice')
        cutorch.setDevice(opt.gpuDevice[1])
    else
        cutorch.setDevice(opt.gpuDevice)
    end
end

-- init logger
local logger = utils.getLogger(opt)

-- print options 
logger:status(utils.colors.info('==> options\r\n') .. utils.colors.success(utils.tableToString(opt))) 

-- load dataset
logger:status(utils.colors.info '==> loading dataset')
local dataset = paths.dofile('./datasets/'..opt.dataset..'.lua')(opt)

-- load module
logger:status(utils.colors.info '==> loading model')
local model 
if string.match(opt.model, '.t7') then
    if opt.trainMode == 'gpu' then
        require 'cunn'
        if opt.cudnnOptimize then
           require 'cudnn'
        end
    end
    -- load pretrained model
    model = torch.load(opt.model)
    if torch.typename(model) == 'nn.DataParallelTable' then
        model = model:get(1)
    end
else 
    -- init model
    model = paths.dofile('models/'..opt.model..'.lua')(opt)
end
if opt.trainMode == 'gpu' then
    require 'cunn'
    if opt.cudnnOptimize then
       require 'cudnn'
       cudnn.convert(model, cudnn)
       cudnn.benchmark = true
    end
end
model = utils.cast(model, opt.trainMode)
local checkResult, modelInfo = utils.testModel(opt, model)
assert(checkResult, utils.colors.warning 'model error')

-- multi gpus support
if not opt.onlyTest and opt.trainMode == 'gpu' and 
    type(opt.gpuDevice) == 'table' and
    table.getn(opt.gpuDevice) > 1 then
    model = utils.makeDataParallelTable(model, opt.gpuDevice)
end
logger:status(utils.colors.success('\r\n' .. model:__tostring()))
logger:status(utils.colors.success(string.format('parameters: %d, memory used: %.2f MBytes\r\n', modelInfo.params, modelInfo.memory.total_size / 1024 / 1024)))

if opt.onlyTest then
    -- start testing
    logger:status(utils.colors.info '==> start testing')
    utils.test(opt, model, dataset, logger)
else
    -- start training
    logger:status(utils.colors.info '==> start training')
    utils.train(opt, model, dataset, logger)
end
