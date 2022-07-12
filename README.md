### Steps to run p4_16 based PTP in Tofino:

1) Navigate to the SDE PATH :
```shell
     cd ~/bf-sde-9.x.x
     export PTP_PATH=<PATH TO PTP FOLDER>
```
2) Set the env variables : 
```shell
     . ./set_sde.bash
```
3) PTP program in p4_16 has multiple profiles :

     
    
     ```shell
          ./p4_build.sh $PTP_PATH/p4_16/p4_src/ptp_switch.p4
     ``` 
     
4) Load the p4 program, and run the control plane API code using :
```shell
     cd $PTP_PATH/p4_16/CP
     ./run.sh
```
   If you want to enable debugs the command is :

```shell
     ./run.sh debug
```

