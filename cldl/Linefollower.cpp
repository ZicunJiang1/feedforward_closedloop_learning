#include "Racer.h"
#include <QApplication>
#include <QtGui>
#include "cldl_filterbank.h"
#include <viewer/Viewer.h>

#include <sstream>
#include <vector>
#include <cerrno>
#include <climits>
#include <cmath>

#include <cstdlib>
#include <string>

using namespace Enki;
using namespace std;

#include "Linefollower.h"

class LineFollower : public ViewerWidget {
protected:
	// The robot
	Racer* racer;
	
	// Is set by the learning rate setter. Do not change here!
	double learningRate = 0;
	
	ClosedloopDeepLearningWithFilterbank* cldl = NULL;

	double* pred = NULL;
	double* err = NULL;

	int outputNeurons;

	FILE* flog = NULL;

	FILE* fcoord = NULL;
	std::string outputDirectory;

	int learningOff = 1;

	long step = 0;

	double avgError = 0.0;

	int successCtr = 0;

	int trackCompletedCtr = 5000;
		
public:
	LineFollower(World *world, QWidget *parent, int seed, const std::vector<int>& layers, const std::string& outputDir = ".") :
		ViewerWidget(world, parent), outputDirectory(outputDir) {

		srand(static_cast<unsigned int>(seed));
		srandom(static_cast<unsigned int>(seed));

		const std::string flogPath =
    		outputDirectory + "/flog.tsv";
		const std::string coordPath =
    		outputDirectory + "/coord.tsv";

		flog = fopen(flogPath.c_str(), "wt");
		fcoord = fopen(coordPath.c_str(), "wt");

		if (!flog || !fcoord) {
   			fprintf(stderr,
            	"Failed to open CLDL output files in %s\n",
            	outputDirectory.c_str());
    		exit(1);
		}

		// setting up the robot
		racer = new Racer(nInputs);
		racer->pos = Point(100, 40);
		racer->angle = 1;
		racer->leftSpeed = speed;
		racer->rightSpeed = speed;
		world->addObject(racer);

		outputNeurons = static_cast<int>(layers.back());

		pred = new double[nInputs];
		err = new double[outputNeurons];

		// setting up deep feedforward learning
		cldl = new ClosedloopDeepLearningWithFilterbank(
			nInputs,
    		layers.data(),
    		static_cast<int>(layers.size()),
    		nFiltersInput,
    		minT,
    		maxT);

		cldl->initNetwork(CLDLNeuron::W_RANDOM_NORM, CLDLNeuron::B_NONE, CLDLNeuron::Act_Tanh);
		cldl->setLearningRate(learningRate);
	}

	~LineFollower() {
		fclose(flog);
		fclose(fcoord);
		delete cldl;
		delete[] pred;
		delete[] err;
	}

	void setLearningRate(double _learningRate) {
		if (_learningRate < 0) return;
		learningRate = _learningRate;
		cldl->setLearningRate(learningRate);	
	}

	inline long getStep() {return step;}

	inline double getAvgError() {return avgError;}

	// here we do all the behavioural computations
	// as an example: line following and obstacle avoidance
	virtual void sceneCompletedHook()
	{
		double leftGround = racer->groundSensorLeft.getValue();
		double rightGround = racer->groundSensorRight.getValue();
		double leftGround2 = racer->groundSensorLeft2.getValue();
		double rightGround2 = racer->groundSensorRight2.getValue();

		fprintf(stderr,"%e\t",racer->pos.x);
		fprintf(fcoord,"%e\t%e\n",racer->pos.x,racer->pos.y);
		// check if we've bumped into a wall
		if ((racer->pos.x<75) ||
		    (racer->pos.x>(maxx-border)) ||
		    (racer->pos.y<border) ||
		    (racer->pos.y>(maxy+border)) ||
		    (leftGround<a) ||
		    (rightGround<a) ||
		    (leftGround2<a) ||
		    (rightGround2<a)) {
			learningOff = 30;
		}
		if (racer->pos.x < border) {
			racer->angle = 0;
			trackCompletedCtr = STEPS_OFF_TRACK;
		}
		trackCompletedCtr--;
		if (trackCompletedCtr < 1) {
			// been off the track for a long time!
			step = MAX_STEPS;
			qApp->quit();
		}
		fprintf(stderr,"%d ",learningOff);
		if (learningOff>0) {
			cldl->setLearningRate(0);
			learningOff--;
		} else {
			cldl->setLearningRate(learningRate);
		}

		fprintf(stderr,"%e %e %e %e ",leftGround,rightGround,leftGround2,rightGround2);
		for(int i=0;i<racer->getNsensors();i++) {
			pred[i] = -(racer->getSensorArrayValue(i))*10;
			// workaround of a bug in Enki
			if (pred[i]<0) pred[i] = 0;
			//if (i>=racer->getNsensors()/2) fprintf(stderr,"%e ",pred[i]);
		}
		double error = (leftGround+leftGround2*2)-(rightGround+rightGround2*2);
		for (int i = 0; i < outputNeurons; i++) {
    		err[i] = error;
		}
		// !!!!
		cldl->doStep(pred,err);
		float vL = (float)((cldl->getOutput(0))*50 +
				   (cldl->getOutput(1))*10 +
				   (cldl->getOutput(2))*2);
		float vR = (float)((cldl->getOutput(3))*50 +
				   (cldl->getOutput(4))*10 +
				   (cldl->getOutput(5))*2);
		
		double erroramp = error * fbgain;
		fprintf(stderr,"%e ",erroramp);
		fprintf(stderr,"%e ",vL);
		fprintf(stderr,"%e ",vR);
		fprintf(stderr,"\n");
		racer->leftSpeed = speed+erroramp+vL;
		racer->rightSpeed = speed-erroramp+vR;

		// documenting
		// if the learning is off we set the error to zero which
		// happens on the edges when the robot is turned violently around
		if (learningOff) error = 0;
       		avgError = avgError + (error - avgError)*avgErrorDecay;
		double absError = fabs(avgError);
		if (absError > SQ_ERROR_THRES) {
			successCtr = 0;
		} else {
			successCtr++;
		}
		if (successCtr>STEPS_BELOW_ERR_THRESHOLD) {
			qApp->quit();
		}
		if (step>MAX_STEPS) {
			qApp->quit();
		}
		
		fprintf(flog,"%e\t",error);
		fprintf(flog,"%e\t",avgError);
		fprintf(flog,"%e\t",absError);
		fprintf(flog,"%e\t%e",vL,vR);
		for(int i=0;i<cldl->getnLayers();i++) {
			fprintf(flog,"\t%e",cldl->getLayer(i)->getWeightDistance());
		}
		fprintf(flog,"\n");

		fflush(flog);
		if ((step%100)==0) {
			for(int i=0;i<cldl->getnLayers();i++) {
				char tmp[512];
				snprintf(tmp,sizeof(tmp),"%s/layer%d.dat",outputDirectory.c_str(),i);
				cldl->getLayer(i)->snapWeights(tmp);
			}
		}

		step++;
	}

};


void singleRun(int argc,
	       char *argv[],
	       double learningrate,
		   int seed,
		   const std::vector<int>& layers,
		   const std::string& outputDirectory,
	       FILE* f = NULL) {
	QApplication app(argc, argv);
	QString filename("loop.png");
	QImage loopImage;
	loopImage = QGLWidget::convertToGLFormat(QImage(filename));
	if (loopImage.isNull()) {
		fprintf(stderr,"Racetrack file not found\n");
		exit(1);
	}
	const uint32_t *bitmap = (const uint32_t*)loopImage.constBits();
	World world(maxx, maxy,
		    Color(1000, 1000, 100),
		    World::GroundTexture(loopImage.width(), loopImage.height(), bitmap));
	world.setRandomSeed(seed);
	srand(static_cast<unsigned int>(seed));
	srandom(static_cast<unsigned int>(seed));
	LineFollower linefollower(
    	&world,
    	nullptr,
    	seed,
		layers,
    	outputDirectory);
	linefollower.setLearningRate(learningrate);
	linefollower.show();
	app.exec();
	fprintf(stderr,"Finished.\n");
	if (f) {
		fprintf(
			f,
			"%e\t%d\t%ld\t%e\n",
			learningrate,
			seed,
			linefollower.getStep(),
			linefollower.getAvgError());
	}
}


void statsRun(int argc,
	      char *argv[]) {
	FILE* f = fopen("stats.dat","wt");

	fprintf(
		f,
		"learning_rate\tseed\tsteps\tavg_error\n");

	const std::vector<int> defaultLayers = {
		9,
		6,
		6
	};

	for(double learningRate = 0.00001f; learningRate < 0.1; learningRate = learningRate * 1.25f) {
	//	srandom(1);
		singleRun(
			argc,
			argv,
			learningRate,
			1,
			defaultLayers,
			".",
			f);
		fflush(f);
	//	srandom(42);
		singleRun(
			argc,
			argv,
			learningRate,
			42,
			defaultLayers,
			".",
			f);
		fflush(f);
	}
	fclose(f);
}


bool parseLayerVector(
    const std::string& text,
    std::vector<int>& layers)
{
    layers.clear();

    std::stringstream stream(text);
    std::string token;

    while (std::getline(stream, token, ',')) {
        if (token.empty()) {
            return false;
        }

        char* end = nullptr;
        errno = 0;

        const long value = std::strtol(
            token.c_str(),
            &end,
            10);

        if (errno != 0 ||
            end == token.c_str() ||
            *end != '\0' ||
            value <= 0 ||
            value > INT_MAX) {
            return false;
        }

        layers.push_back(static_cast<int>(value));
    }

    if (layers.empty()) {
        return false;
    }

    if (layers.back() != 6) {
        fprintf(
            stderr,
            "The output layer must contain exactly 6 neurons.\n");

        return false;
    }

    return true;
}

bool parseDouble(
    const char* text,
    double& value)
{
    char* end = nullptr;
    errno = 0;

    value = std::strtod(text, &end);

    if (errno != 0 ||
        end == text ||
        *end != '\0' ||
        !std::isfinite(value)) {
        return false;
    }

    return true;
}

bool parseInt(
    const char* text,
    int& value)
{
    char* end = nullptr;
    errno = 0;

    const long parsed = std::strtol(
        text,
        &end,
        10);

    if (errno != 0 ||
        end == text ||
        *end != '\0' ||
        parsed < INT_MIN ||
        parsed > INT_MAX) {
        return false;
    }

    value = static_cast<int>(parsed);
    return true;
}



int main(int argc, char *argv[]) {
    if (argc < 2) {
		fprintf(
			stderr,
			"Usage:\n"
			"  Single run:\n"
			"    %s 0 <learning_rate> <seed> <layers> "
			"[output_directory]\n"
			"\n"
			"  Example:\n"
			"    %s 0 0.0008 42 9,6,6 DataDL\n"
			"\n"
			"  Stats run:\n"
			"    %s 1\n",
			argv[0],
			argv[0],
			argv[0]);

		return 1;
	}

	int mode = 0;

	if (!parseInt(argv[1], mode)) {
		fprintf(
			stderr,
			"Invalid mode: %s\n",
			argv[1]);

		return 1;
	}

    switch (mode) {
    case 0: {
    	if (argc < 5 || argc > 6) {
        	fprintf(
            	stderr,
            	"Usage: %s 0 <learning_rate> <seed> "
            	"<layers> [output_directory]\n",
            	argv[0]);
        	return 1;
    	}

    	double learningRate = 0.0;

    	if (!parseDouble(argv[2], learningRate) ||
        	learningRate <= 0.0) {
        		fprintf(
            	stderr,
            	"Invalid learning rate: %s\n",
            	argv[2]);
        	return 1;
    	}

    	int seed = 0;

    	if (!parseInt(argv[3], seed)) {
        	fprintf(
            	stderr,
            	"Invalid seed: %s\n",
            	argv[3]);
        	return 1;
    	}

    	std::vector<int> layers;

    	if (!parseLayerVector(argv[4], layers)) {
        	fprintf(
            	stderr,
            	"Invalid layer vector: %s\n"
            	"Expected format such as 9,6,6. "
            	"The final layer must contain 6 neurons.\n",
            	argv[4]);
        	return 1;
    	}

    	const std::string outputDirectory =
        	argc == 6 ? argv[5] : ".";

    	fprintf(
        	stderr,
        	"Starting CLDL single run:\n"
        	"  learning rate: %.17g\n"
        	"  seed: %d\n"
        	"  layers: %s\n"
        	"  output: %s\n",
        	learningRate,
        	seed,
        	argv[4],
        	outputDirectory.c_str());

    	singleRun(
        	argc,
        	argv,
        	learningRate,
        	seed,
        	layers,
        	outputDirectory);

    	break;
	}

    case 1:
        statsRun(argc, argv);
        break;

    default:
        fprintf(stderr, "Unknown mode: %d\n", mode);
        return 1;
    }

    return 0;
}