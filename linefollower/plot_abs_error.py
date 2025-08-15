#!/usr/bin/python3
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation


# Creates a scrolling data display: column col of the tsvfile
class RealtimePlotWindow:

    def __init__(self,tsvfile,col):
        self.col = col
        self.tsvfile = tsvfile
        # create a plot window
        self.fig, self.ax = plt.subplots()
        self.ax.set_ylim(-0.02, 0.02)
        # that's our plotbuffer
        self.plotbuffer = np.zeros(2000)
        # create an empty line
        self.line, = self.ax.plot(self.plotbuffer)
        # start the animation
        self.ani = animation.FuncAnimation(self.fig, self.update, interval=100)

    # updates the plot
    def update(self, data):
        try:
            data = np.loadtxt(self.tsvfile);
            self.plotbuffer = np.append(data[-2000:,self.col],np.zeros(2000))
            self.plotbuffer = self.plotbuffer[:2000]
            self.line.set_ydata(self.plotbuffer)
        except:
            pass
        return self.line,


# Create an instance of an animated scrolling window

column_idx_map = {
    'unamplified_error': 0,
    'average_error':1,
    'absolute_error':2,
    'left_steering_velocity':3,
    'right_steering_velocity':4,
    'layer_1_wt_dist':4,
    'layer_2_wt_dist':5,
    'layer_3_wt_dist':6
}

realtimePlotWindow = RealtimePlotWindow("flog.tsv",column_idx_map['absolute_error'])

# show the plot and start the animation
plt.show()

print("finished")
