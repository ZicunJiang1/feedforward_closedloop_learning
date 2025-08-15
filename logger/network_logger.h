#ifndef NETWORK_LOGGER_H
#define NETWORK_LOGGER_H

#include "layer_logger.h"
#include "fcl.h"
#include <iostream>

class NetworkLogger : public Logger
{
public:
	NetworkLogger(FeedforwardClosedloopLearning *network);
	void logLayers();
	void log() override
	{
		for (int i{0}; i < layerCount; ++i)
		{
			auto layer = network->getLayer(i);
			fprintf(logFile, "%d\t%d\n", layer->getNneurons(), layer->getNinputs());
		}
		fflush(logFile);
	}

private:
	FeedforwardClosedloopLearning *network;
	std::vector<LayerLogger> layerLoggers{};
	int layerCount;
};

#endif