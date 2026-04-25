FROM swipl:latest

WORKDIR /experiment

COPY experiment.pl .

CMD ["swipl", "-s", "experiment.pl"]
