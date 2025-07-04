FROM ubuntu:latest

ENV FLUTTER_HOME=${HOME}/sdks/flutter 
ENV PATH ${PATH}:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin

USER root

RUN apt update

RUN apt install -y git curl unzip

# Print the Ubuntu version. Useful when there are failing tests.
RUN cat /etc/lsb-release

# Invalidate the cache when flutter pushes a new commit.
#
# This step creates a file in the Docker container that holds the latest commit hash
# from Flutter master. As a result, this step will invalidate itself whenever that
# hash changes. Then, when this step invalidates, it forces Docker to run the following
# steps again, which includes the `git clone` of Flutter.
ADD https://api.github.com/repos/flutter/flutter/git/refs/heads/master ./flutter-latest-master

# Clone Flutter into the Docker container.
RUN git clone https://github.com/flutter/flutter.git ${FLUTTER_HOME}

# Print out Flutter's status in case something is wrong with Flutter inside the container.
RUN flutter doctor

# Copy the whole project.
#
# In the most common scenario, this copies the app/package under test. However, in a mono-repo
# situation, this copies the whole mono-repo, because the mono-repo might have local dependencies
# pointing to each other within the mono-repo.
COPY ./ /golden_tester
