#include "network_logger.h"

NetworkLogger::NetworkLogger(FeedforwardClosedloopLearning *network) : Logger("network-properties.tsv")
{
    this->network = network;
    char filenameBuffer[100];
    layerCount = network->getNumLayers();
    for (int i{0}; i < layerCount; ++i)
    {
        snprintf(filenameBuffer, sizeof(filenameBuffer), "layer-%d-log.tsv", i);
        layerLoggers.push_back(LayerLogger(network->getLayer(i), filenameBuffer));
    }
}

void NetworkLogger::logLayers()
{
    for (auto i : layerLoggers)
    {
        i.log();
    }
}
