#ifndef LAYER_LOGGER_H
#define LAYER_LOGGER_H

#include "fcl.h"
#include "logger.h"

class LayerLogger : public Logger
{
public:
	LayerLogger(FCLLayer *layer, const char *fileName);
	void log() override
	{
		// Printing each neuron's inputs
		for (int i{0}; i < layer->getNneurons(); ++i)
		{
			auto neuron = layer->getNeuron(i);
			for (int j{0}; j < neuron->getNinputs(); ++j)
			{
				fprintf(logFile, "%e\t", neuron->getInput(j));
				fflush(logFile);
			}
		}
		// Printing errors of each neuron
		for (int i{0}; i < layer->getNneurons(); ++i)
		{
			auto neuron = layer->getNeuron(i);
			fprintf(logFile, "%e\t", neuron->getError());
			fflush(logFile);
		}

		// Printing weights between each input of each neuron
		// Creates nNeurons * nInputs columns
		for (int i{0}; i < layer->getNneurons(); ++i)
		{
			auto neuron = layer->getNeuron(i);
			for (int j{0}; j < neuron->getNinputs(); ++j)
			{
				fprintf(logFile, "%e\t", neuron->getWeight(j));
				fflush(logFile);
			}
		}
		// Printing bias weights of each neuron
		for (int i{0}; i < layer->getNneurons(); ++i)
		{
			auto neuron = layer->getNeuron(i);
			fprintf(logFile, "%e\t", neuron->getBiasWeight());
			fflush(logFile);
		}

		// Printing outputs of each neuron
		for (int i{0}; i < layer->getNneurons(); ++i)
		{
			auto neuron = layer->getNeuron(i);
			fprintf(logFile, "%e\t", neuron->getOutput());
			fflush(logFile);
		}

		fprintf(logFile, "\n");
		fflush(logFile);
	}

private:
	FCLLayer *layer;
};

#endif