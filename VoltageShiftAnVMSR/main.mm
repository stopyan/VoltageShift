//
//  main.mm
//
//
//  Created by SC Lee on 12/09/13.
//  Copyright (c) 2017 SC Lee . All rights reserved.
//
//
//  MSR Kext Access modifiyed from AnVMSR by  Andy Vandijck Copyright (C) 2013 AnV Software
//
//   This is licensed under the
//      GNU General Public License v3.0
//
//
//


#import <Foundation/Foundation.h>
#import <sstream>
#import <vector>
#import <string>


#ifndef MAP_FAILED
#define MAP_FAILED    ((void *)-1)
#endif

//#define DEBUG 1

#define kAnVMSRClassName "VoltageShiftAnVMSR"


#define MSR_OC_MAILBOX			0x150
#define MSR_OC_MAILBOX_CMD_OFFSET	32
#define MSR_OC_MAILBOX_RSP_OFFSET	32
#define MSR_OC_MAILBOX_DOMAIN_OFFSET	40
#define MSR_OC_MAILBOX_BUSY_BIT		63
#define OC_MAILBOX_READ_VOLTAGE_CMD	0x10
#define OC_MAILBOX_WHITE_VOLTAGE_CMD	0x11
#define OC_MAILBOX_VALUE_OFFSET		20
#define OC_MAILBOX_RETRY_COUNT		5

#define MCHBAR_ADDR_POWER   0xfed159a0
#define MSR_ADDR_POWER      0x610
#define MSR_ADDR_UNITS      0x606

io_connect_t connect ;
Boolean damagemode = false;

io_service_t service ;

double basefreq = 0;
double maxturbofreq = 0;
double multturbofreq = 0;
double fourthturbofreq = 0;
double power_units = 0;
uint64 dtsmax = 0;
uint64 tempoffset = 0;

enum {
    AnVMSRActionMethodRDMSR = 0,
    AnVMSRActionMethodWRMSR = 1,
    AnVMSRActionMethodPrepareMap = 2,
    AnVMSRNumMethods
};

typedef struct {
	UInt32 action;
    UInt32 msr;
    UInt64 param;
} inout;

typedef struct {
    UInt64 addr;
    UInt64 size;
} map_t;

typedef struct {
    bool short_enabled;
    float short_power;
    float short_time;
    bool long_enabled;
    float long_power;
    float long_time;
} power_limit;

io_service_t getService() {
	io_service_t service = 0;
	mach_port_t masterPort;
	io_iterator_t iter;
	kern_return_t ret;
	io_string_t path;
	
	ret = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (ret != KERN_SUCCESS) {
		printf("Can't get masterport\n");
		goto failure;
	}
	
	ret = IOServiceGetMatchingServices(masterPort, IOServiceMatching(kAnVMSRClassName), &iter);
	if (ret != KERN_SUCCESS) {
		printf("VoltageShift.kext is not running\n");
		goto failure;
	}
	
	service = IOIteratorNext(iter);
	IOObjectRelease(iter);
	
	ret = IORegistryEntryGetPath(service, kIOServicePlane, path);
	if (ret != KERN_SUCCESS) {
		// printf("Can't get registry-entry path\n");
		goto failure;
	}
	
failure:
	return service;
}

void usage(const char *name)
{
    
    printf("--------------------------------------------------------------------------\n");
    printf("VoltageShift Undervoltage Tool v 1.1 for Intel Haswell+ \n");
    printf("Copyright (C) 2017 SC Lee \n");
    printf("--------------------------------------------------------------------------\n");

    printf("Usage:\n");
    printf("set voltage:  \n    %s offset <CPU> <GPU> <CPUCache> <SA> <AI/O> <DI/O>\n\n", name);
    printf("set boot and auto apply:\n  sudo %s buildlaunchd <CPU> <GPU> <CPUCache> <SA> <AI/O> <DI/O> <PL2 POWER> <PL2 WINDOW> <PL1 POWER> <PL1 WINDOW> <UpdateMins (0 only apply at bootup)> \n\n", name);
    printf("remove boot and auto apply:\n    %s removelaunchd \n\n", name);
    printf("get info of current setting:\n    %s info \n\n", name);
    printf("continuous monitor of CPU:\n    %s mon \n\n", name);
    printf("read MSR: %s read <HEX_MSR>\n\n", name);
    printf("write MSR: %s write <HEX_MSR> <HEX_VALUE>\n\n", name);
    printf("read memory: %s remem <HEX_ADDR>\n\n", name);
    printf("write memory: %s wrmem <HEX_ADDR> <HEX_VALUE>\n\n", name);
    printf("set power limit:  \n    %s powerlimit <PL2 POWER> <PL2 WINDOW> <PL1 POWER> <PL1 WINDOW>\n\n", name);
}

unsigned long long hex2int(const char *s)
{
    return strtoull(s,NULL,16);
}

// Read OC Mailbox
// Ref of Intel Turbo Boost Max Technology 3.0 legacy (non HWP) enumeration driver
// https://github.com/torvalds/linux/blob/master/drivers/platform/x86/intel_turbo_max_3.c
//
//
//    offset 0x40 is the OC Mailbox Domain bit relative for:
//
//
//   domain : 0 - CPU
//            1 - GPU
//            2 - CPU Cache
//            3 - System Agency
//            4 - Analogy I/O
//            5 - Digtal I/O
//
//






int writeOCMailBox (int domain,int offset){
    

    
    if (offset > 0 && !damagemode){
        printf("--------------------------------------------------------------------------\n");
        printf("VoltageShift offset Tool\n");
        printf("--------------------------------------------------------------------------\n");
        printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
        printf("Your settings require overclocking. This May Damage you Computer !!!! \n");
        printf("use --damaged for override\n");
        printf("     usage: voltageshift --damage offset ... for run\n");
        printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
        printf("--------------------------------------------------------------------------\n");
        
        return -1;
    }
    
    if (offset < -250  && !damagemode){
        printf("--------------------------------------------------------------------------\n");
        printf("VoltageShift offset Tool\n");
        printf("--------------------------------------------------------------------------\n");
        printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
        printf("Your settings are too low. Are you sure you want thosse values \n");
        printf("use --damaged for override\n");
        printf("     usage: voltageshift --damage offset ... for run\n");
        printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
        printf("--------------------------------------------------------------------------\n");

        return -1;
    }
    
    if (damagemode){
        printf("--------------------------------------------------------------------------\n");
        printf("VoltageShift offset Tool Damage Mode in Process \n");
        printf("--------------------------------------------------------------------------\n");
        printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    }
    
    uint64 offsetvalue;
    
    if (offset < 0){
        offsetvalue = 0x1000 + ((offset) * 2);
    }else{
        offsetvalue = offset * 2;
    }
    
    
    
    uint64 value = offsetvalue << OC_MAILBOX_VALUE_OFFSET;
    
    
    // MSR 0x150 OC Mailbox 0x11 for write of voltage offset values
    uint64 cmd = OC_MAILBOX_WHITE_VOLTAGE_CMD;
    int ret;
    
    inout in;
    inout out;
    size_t outsize = sizeof(out);
    
    /* Issue favored core read command */

    value |= cmd << MSR_OC_MAILBOX_CMD_OFFSET;
     /* Domain for the values set for */
    value |= ((uint64)domain) << MSR_OC_MAILBOX_DOMAIN_OFFSET;
  
    /* Set the busy bit to indicate OS is trying to issue command */
    value |= ((uint64)0x1) << MSR_OC_MAILBOX_BUSY_BIT;
   
    
    
    in.msr = (UInt32)MSR_OC_MAILBOX;
    in.action = AnVMSRActionMethodWRMSR;
    in.param = value;
    
  //  printf("WRMSR %x with value 0x%llx\n", (unsigned int)in.msr, (unsigned long long)in.param);
    
   // return (0);
    
    
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodWRMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    
    
    
    
    if (ret != KERN_SUCCESS) {
        printf("cpu OC mailbox write failed\n");
        return 0;
    }
    
    return 0;
  
    
}



int readOCMailBox (int domain){
  
    
    // MSR 0x150 OC Mailbox 0x10 for read of voltage offset values
    uint64 value, cmd = OC_MAILBOX_READ_VOLTAGE_CMD;
    int ret, i;
    
    inout in;
    inout out;
    size_t outsize = sizeof(out);
    
    /* Issue favored core read command */
    value = cmd << MSR_OC_MAILBOX_CMD_OFFSET;
    /* Domain for the values set for */
    value |= ((uint64)domain) << MSR_OC_MAILBOX_DOMAIN_OFFSET;
    /* Set the busy bit to indicate OS is trying to issue command */
    value |= ((uint64)0x1) << MSR_OC_MAILBOX_BUSY_BIT;
    
    
    in.msr = (UInt32)MSR_OC_MAILBOX;
    in.action = AnVMSRActionMethodWRMSR;
    in.param = value;
    
    //printf("WRMSR %x with value 0x%llx\n", (unsigned int)in.msr, (unsigned long long)in.param);
    
    
    

    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodWRMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );

    

    
  
    if (ret != KERN_SUCCESS) {
        printf("cpu OC mailbox write failed\n");
        return 0;
    }
    
    
    for (i = 0; i < OC_MAILBOX_RETRY_COUNT; ++i) {
        
        in.msr = MSR_OC_MAILBOX;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read voltage 0xe7 \n");
            
            
        }
        
        

     
        
        if (out.param & (((uint64)0x1) << MSR_OC_MAILBOX_BUSY_BIT)) {
            printf(" OC mailbox still processing\n");
            ret = -EBUSY;
            continue;
        }
        
        if ((out.param >> MSR_OC_MAILBOX_RSP_OFFSET) & 0xff) {
            printf("OC mailbox cmd failed\n");
           
            break;
        }
     
        

        
        
        break;
    }
    
  //  printf("RDMSR %x returns value 0x%llx\n", (unsigned int)in.msr, (unsigned long long)out.param);

    int returnvalue = (int)(out.param >> 20) & 0xFFF;
    if (returnvalue > 2047){
        returnvalue = -(0x1000-returnvalue);
    }
    
    return returnvalue / 2 ;
    
}


int showcpuinfo(){
    
    kern_return_t ret;
    
    inout in;
    inout out;
    size_t outsize = sizeof(out);
    
    double freq = 0;
    double powerpkg = 0;
    double powercore = 0;
    
    
    
    in.action = AnVMSRActionMethodRDMSR;
    in.param = 0;
    
    if (basefreq==0){
    in.msr = 0xce;
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't read  0xce ");
       
        return (1);
        
    }
    
    basefreq = (double)(out.param >> 8 & 0xFF ) * 100;
        
    }
    
    if (power_units == 0){
    in.msr = 0x606;
    in.action = AnVMSRActionMethodRDMSR;
    in.param = 0;
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't read  0x0606 ");
        return (1);

        
    }
    
    
    
   // double power_units = pow(0.5,(double)(out.param &0xf));
    power_units =pow(0.5,(double)((out.param>>8)&0x1f)) * 10;
    }
    
    if (maxturbofreq == 0){
        in.msr = 0x1AD;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0x01AD ");
            return (1);
            
        }
        
        
        
        // double power_units = pow(0.5,(double)(out.param &0xf));
          maxturbofreq =(double)(out.param & 0xff) * 100.0;
        multturbofreq =(double)(out.param>>8 & 0xff) * 100.0;
        fourthturbofreq =(double)(out.param>>24 &0xff) * 100.0;
        printf("CPU BaseFreq: %.0f, CPU MaxFreq(1/2/4): %.0f/%.0f/%.0f (mhz) \n",basefreq ,maxturbofreq,multturbofreq,fourthturbofreq);
    }
    
    
    
    
    
    
    
  //  do {
        
        
        in.msr = 0x611;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0x611 ");
            return (1);

            
        }
        
        
        
        
        
        unsigned long long lastpowerpkg = out.param;
        
        in.msr = 0x639;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0x639 ");
            return (1);

            
        }
        
        
        
        
        
        unsigned long long lastpowercore = out.param;
        

         /*
        
        
        in.msr = 0xe7;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0xe7 ");
            return (1);

            
        }
        
        unsigned long long le7 = out.param;
        //   printf("RDMSR %x returns value 0x%llx\n", (unsigned int)in.msr, le7);
        
        in.msr = 0xe8;
        
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read 0xe8 ");
            return (1);

            
        }
        unsigned long long le8 = out.param;
        
   
        
        //uint64 firsttime = clock_gettime_nsec_np(CLOCK_REALTIME);
          */
        uint64 firsttime;
     
     
    
        
        in.msr = 0x637;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
           firsttime = clock_gettime_nsec_np(CLOCK_REALTIME)/1000;
           // printf("Can't read  0xe7 ");
          //  return (1);
            
            
        }else{
            firsttime = out.param /24 ;
        }
        
        
        
        usleep(100000);
        
        /*
        
        in.msr = 0xe7;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0xe7 ");
            return (1);

            
        }
        
        
        unsigned long long e7 = out.param;
        
        
        
        
        in.msr = 0xe8;
        
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read 0xe8 ");
            
            return (1);

        }
        unsigned long long e8 = out.param;
         */
        
        in.msr = 0x637;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        
        uint64 secondtime;
        
        if (ret != KERN_SUCCESS)
        {
            secondtime = clock_gettime_nsec_np(CLOCK_REALTIME)/1000;
            // printf("Can't read  0xe7 ");
            //  return (1);
            
            
        }else{
            secondtime = out.param /24;
        }
        
        
  
        
        //  uint64 secondtime = clock_gettime_nsec_np(CLOCK_REALTIME);
        
        secondtime -= firsttime;
        double second = (double)secondtime / 100000;
        
        //   freq =   basefreq  / second * (  ((double)e8-le8)/((double)e7-le7));
        
        //    printf("RDMSR %x volt %f\n", (unsigned int)in.msr, basefreq);
        
        
        
        in.msr = 0x611;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read power 0x611 ");
            
            return (1);

        }
        
         powerpkg = power_units * ((double)out.param - lastpowerpkg) / second;
        
        
        in.msr = 0x639;
        in.action = AnVMSRActionMethodRDMSR;
        in.param = 0;
        ret = IOConnectCallStructMethod(connect,
                                        AnVMSRActionMethodRDMSR,
                                        &in,
                                        sizeof(in),
                                        &out,
                                        &outsize
                                        );
        
        if (ret != KERN_SUCCESS)
        {
            printf("Can't read  0x639 ");
            return (1);

            
        }
        
        
        
        
        powercore =  power_units * ((double)out.param - lastpowercore) / second;

        
        
        
        
        
        
        
    //}while( freq < 200.0 || freq > (maxturbofreq + 100));
    
    


    
  
    
    
    
    
    in.msr = 0x198;
    
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't read voltage 0x198\n");
        return (1);

        
    }
    
    

    
    
    double voltage  = out.param >> 32 & 0xFFFF;
    freq = out.param >> 8 & 0xFF;
    freq /= 10;
    voltage /= pow(2,13);
    
    if (dtsmax==0){
    
    in.msr = 0x1A2;
    
    
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't read voltage 0x1A2 \n");
        
        return (1);

    }
    

     dtsmax = out.param >> 16 & 0xFF;
     
    tempoffset = out.param >> 24 & 0x3F;
    }
    
    in.msr = 0x19C;
    
    
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't read voltage 0x19C \n");
        
        return (1);
    }
    
        uint64 margintothrottle = out.param >> 16 & 0x3F;
    
    
    

    
    
    
    
    
    
    

    

    
    uint64 temp = dtsmax - tempoffset - margintothrottle;
    
    
    
    printf("CPU Freq: %2.1fghz, Voltage: %.4fv, Power:pkg %2.2fw /core %2.2fw,Temp: %llu c", freq,voltage,powerpkg,powercore,temp);
    

    return (0);
    

    
    
    
}

int access_power_limit(power_limit *pl, bool write);

int setoffsetdaemons(int argc,const char * argv[]){
    power_limit pl;
    for (int i=0; i<argc-2; i++){
        if (i < 6) {
            int offset = (int)strtol((char *)argv[i+2],NULL,10);
            if (readOCMailBox(i) != offset){
                 writeOCMailBox(i, offset);
            }
        } else {
            float val = strtof((char *)argv[i+2], NULL);
            if (i == 6) {
                pl.long_power = val;
            } else if (i == 7) {
                pl.long_time = val;
            } else if (i == 8) {
                pl.short_power = val;
            } else if (i == 9) {
                pl.short_time = val;
            }
        }
    }
    pl.long_enabled = true;
    pl.short_enabled = true;
    access_power_limit(&pl, true);

    return(0);
}

int setoffset(int argc,const char * argv[]){
    
    long cpu_offset = 0;
    long gpu_offset = 0;
    long cpuccache_offset = 0;
    long systemagency_offset = 0;
    long analogy_offset = 0;
    long digitalio_offset = 0;
    
    if (argc >= 3)
    {
        cpu_offset = strtol((char *)argv[2],NULL,10);
        if (argc >=4)
            gpu_offset = strtol((char *)argv[3],NULL,10);
        if (argc >=5)
            cpuccache_offset = strtol((char *)argv[4],NULL,10);
        if (argc >=6)
            systemagency_offset = strtol((char *)argv[5],NULL,10);
        if (argc >=7)
            analogy_offset = strtol((char *)argv[6],NULL,10);
        if (argc >=8)
            digitalio_offset = strtol((char *)argv[7],NULL,10);
    } else {
        usage(argv[0]);
        
        return(1);
    }
    
    printf("--------------------------------------------------------------------------\n");
    printf("VoltageShift offset Tool\n");
    printf("--------------------------------------------------------------------------\n");

    if (argc >= 3)
        printf("Before CPU voltageoffset: %dmv\n",readOCMailBox(0));
    if (argc >= 4)
        printf("Before GPU voltageoffset: %dmv\n",readOCMailBox(1));
    if (argc >= 5)
        printf("Before CPU Cache: %dmv\n",readOCMailBox(2));
    if (argc >= 6)
        printf("Before System Agency: %dmv\n",readOCMailBox(3));
    if (argc >= 7)
        printf("Before Analogy I/O: %dmv\n",readOCMailBox(4));
    if (argc >= 8)
        printf("Before Digital I/O: %dmv\n",readOCMailBox(5));
    printf("--------------------------------------------------------------------------\n");

    if (argc >= 3)
        writeOCMailBox(0, (int)cpu_offset);
    if (argc >= 4)
        writeOCMailBox(1, (int)gpu_offset);
    if (argc >= 5)
        writeOCMailBox(2, (int)cpuccache_offset);
    if (argc >= 6)
        writeOCMailBox(3, (int)systemagency_offset);
    
    if (argc >= 7)
        writeOCMailBox(4,(int) analogy_offset);
    if (argc >= 8)
        writeOCMailBox(5, (int)digitalio_offset);
    
    if (argc >= 3)
        printf("After CPU voltageoffset: %dmv\n",readOCMailBox(0));
    if (argc >= 4)
        printf("After GPU voltageoffset: %dmv\n",readOCMailBox(1));
    if (argc >= 5)
        printf("After CPU Cache: %dmv\n",readOCMailBox(2));
    if (argc >= 6)
        printf("After System Agency: %dmv\n",readOCMailBox(3));
    if (argc >= 7)
        printf("After Analogy I/O: %dmv\n",readOCMailBox(4));
    if (argc >= 8)
        printf("After Digital I/O: %dmv\n",readOCMailBox(5));
    printf("--------------------------------------------------------------------------\n");
    
    return(0);
}


void unloadkext() {
    
    if(connect)
    {
       kern_return_t ret = IOServiceClose(connect);
        if (ret != KERN_SUCCESS)
        {
          
        }
    }
    
    if(service)
        IOObjectRelease(service);

    std::stringstream output;
    output << "sudo kextunload -q -b "
      << "com.sicreative.VoltageShift"
    << " " ;
    
    system(output.str().c_str());

}

void loadkext() {
    
    std::stringstream output;
    output << "sudo kextutil -q -r ./  -b "
    << "com.sicreative.VoltageShift"
    << " " ;

    system(output.str().c_str());
    
    output.str("");
    
    output << "sudo kextutil -q -r /Library/Application\\ Support/VoltageShift/ -b "
    << "com.sicreative.VoltageShift"
    << " " ;
    
    system(output.str().c_str());
    
    
}

void removeLaunchDaemons(){
    std::stringstream output;
    
    output.str("sudo rm /Library/LaunchDaemons/com.sicreative.VoltageShift.plist ");
    system(output.str().c_str());
    
    output.str("sudo rm -R /Library/Application\\ Support/VoltageShift/ ");
    system(output.str().c_str());
    
    // Check process of build sucessful
    int error  = 0;
    
    FILE *fp = popen("sudo ls /Library/LaunchDaemons/com.sicreative.VoltageShift.plist","r");
    
    if (fp != NULL)
    {
        char str [255] ;
       
        
        while (fgets(str, 255, fp) != NULL){
            printf("%s", str);
            if (strstr(str,"/Library/LaunchDaemons/com.sicreative.VoltageShift.plist")!=NULL) {
                error ++;
            }
        }
        
        
        
        
        
        pclose(fp);
    }
    
    
    fp = popen("sudo ls /Library/Application\\ Support/VoltageShift/","r");
    if (fp != NULL)
    {
        char str [255] ;
        
        
        while (fgets(str, 255, fp) != NULL){
            
            printf("%s", str);
            
            if (strstr(str,"VoltageShift.kext")!=NULL) {
                error ++;
                continue;
            }
            
            if (strstr(str,"voltageshift")!=NULL) {
                error ++;
            }
            
        }
     //   printf("%s", str);
        
        
        
        pclose(fp);
    }
    
    // error message
    
    if (error != 0){
        printf("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n");
        printf("--------------------------------------------------------------------------\n");
        printf("VoltageShift remove Launchd daemons Tool\n");
        printf("--------------------------------------------------------------------------\n");
        printf("    Can't Remove the launchd.  No Sucessful of delete the files,\n\n");

       
               
        printf("or manual delete by:\n");
        
        printf("      sudo rm /Library/LaunchDaemons/com.sicreative.VoltageShift.plist\n ");
        printf("      sudo rm -R /Library/Application\\ Support/VoltageShift \n");

        printf("--------------------------------------------------------------------------\n");
        printf("--------------------------------------------------------------------------\n");
        
        
        return ;
    }
    
    printf("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n");
    printf("--------------------------------------------------------------------------\n");
    printf("VoltageShift remove Launchd daemons Tool\n");
    printf("--------------------------------------------------------------------------\n");
    printf("    Sucessed Full remove the Launchd daemons\n");
    printf("    Fully Switch off (no reboot) for the system back to \n        non-undervoltage status\n");
    printf("--------------------------------------------------------------------------\n");
    printf("Don't forget enable the CSR protect by following methond:\n");
    printf("1. Boot start by Command-R to recovery mode :\n");
    printf("2. In \"Terminal\" >> csrutil enable  \n");
    printf("--------------------------------------------------------------------------\n");
    printf("--------------------------------------------------------------------------\n");
    

    
    
    


}

void writeLaunchDaemons(std::vector<float>  values = {0},int min = 160  ) {
    std::stringstream output;
    
    if (min>720){
          printf("------------------------------------\n");
        printf("Out of Interval setting, please select between 0 (Run only bootup) to 720mins \n");
        printf("------------------------------------\n");
        return;

    }
        
    

    printf("Build for LaunchDaemons of Auto Apply for VoltageShift\n");
    printf("------------------------------------\n");
   
    
   
  output.str("sudo rm -R /Library/Application\\ Support/VoltageShift/");
    
     output.str("sudo rm /Library/LaunchDaemons/com.sicreative.VoltageShift.plist");
     system(output.str().c_str());
    
     output.str("");
    
    //add 0 for no user input field
    for (int i=(int)values.size();i<10;i++){
        values.push_back(0);
    }
    
   output << "sudo echo \""
   << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
   << "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
   <<  "<plist version=\"1.0\">"
   << "<dict>"
    << "<key>RunAtLoad</key><true/>"
   << "<key>Label</key>"
   << "<string>com.sicreative.VoltageShift</string>"
   << "<key>ProgramArguments</key>"
   << "<array>"
   << "<string>/Library/Application Support/VoltageShift/voltageshift</string>"
   << "<string>offsetdaemons</string>";
   
    for (int i=0;i<values.size();i++){
       output << "<string>"
       << values[i]
       << "</string>";
    }
      
   output << "</array>";
    
    
    
    // Change of use StartCalendarInterval for better support asleep (suspend to disk) wakeup
   /*
   output << "<key>StartInterval</key>"
   << "<integer>"
   << min
   << "</integer>";
    
    */
    
    
    if (min>0){
    
    output << "<key>StartCalendarInterval</key>"
    << "<array>";
    


    if (min<=60 && 60%min==0){
        for (int i=0;i<60;i+=min){
          output  << "<dict>"
            << "<key>Minute</key>"
            << "<integer>"
            << i
            << "</integer>"
            << "</dict>";
        }

    }else{
        for (int i=0;i<1440;i+=min){
            output  << "<dict>"
            << "<key>Hour</key>"
            << "<integer>"
            << i/60
            << "</integer>"
            << "<key>Minute</key>"
            << "<integer>"
            << i%60
            << "</integer>"
            << "</dict>";
        }
        
    }
    
    output << "</array>";

    }
   output << "</dict>"
   << "</plist>"
    << "\" > /Library/LaunchDaemons/com.sicreative.VoltageShift.plist"
    << " ";
    system(output.str().c_str());
    
    output.str("sudo chown  root:wheel /Library/LaunchDaemons/com.sicreative.VoltageShift.plist ");
    
     system(output.str().c_str());
 output.str("sudo mkdir  /Library/Application\\ Support/VoltageShift/ ");
    system(output.str().c_str());
    
      output.str("sudo cp  -R ./VoltageShift.kext /Library/Application\\ Support/VoltageShift/ ");
    system(output.str().c_str());
       output.str("sudo cp  ./voltageshift /Library/Application\\ Support/VoltageShift/ ");
    system(output.str().c_str());
      output.str("sudo chown  -R root:wheel /Library/Application\\ Support/VoltageShift/VoltageShift.kext ");
    system(output.str().c_str());
      output.str("sudo chown  root:wheel /Library/Application\\ Support/VoltageShift/voltageshift ");
    system(output.str().c_str());
    
    
    
    // Check process of build sucessful
    int error  = 3;
    
    FILE *fp = popen("sudo ls /Library/LaunchDaemons/com.sicreative.VoltageShift.plist","r");

    if (fp != NULL)
    {
        char str [255] ;
        
        
        while (fgets(str, 255, fp) != NULL){
            printf("%s", str);
            if (strstr(str,"/Library/LaunchDaemons/com.sicreative.VoltageShift.plist")!=NULL) {
                error --;
            }
        }
        
      
        
      
        
        pclose(fp);
    }
    
    
    fp = popen("sudo ls /Library/Application\\ Support/VoltageShift/","r");
    if (fp != NULL)
    {
        char str [255] ;
       
        
        while (fgets(str, 255, fp) != NULL){
         
            printf("%s", str);
            
            if (strstr(str,"VoltageShift.kext")!=NULL) {
                error --;
                continue;
            }
            
            if (strstr(str,"voltageshift")!=NULL) {
                error --;
            }

        }
          //  printf("%s", str);
        
        
        
        pclose(fp);
    }

// error message
    
    if (error != 0){
        printf("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n");
        printf("--------------------------------------------------------------------------\n");
        printf("VoltageShift builddaemons Tool\n");
        printf("--------------------------------------------------------------------------\n");
        printf("    Can't build the launchd.  Can´t create the files, please use:\n\n");
                                                                                   
        printf("             sudo ./voltageshift buildlaunchd .... \n\n");
        printf("for Root privilege.\n");
        printf("--------------------------------------------------------------------------\n");
        printf("--------------------------------------------------------------------------\n");
     
        
        return ;
    }

    
    
    
//Sucess and Caution message
    
    printf("\n\n\n\n\n");
    printf("--------------------------------------------------------------------------\n");
    printf("VoltageShift builddaemons Tool\n");
    printf("--------------------------------------------------------------------------\n");

    printf("Finished installing the LaunchDaemons, Please Reboot\n\n");
    printf("--------------------------------------------------------------------------\n");
    
    printf("The system will apply the below undervoltage setting \n values for boot, and Amend every %d mins\n", min);

   printf("--------------------------------------------------------------------------\n");
     printf("************************************************************************\n");
    printf("Please CONFIRM and TEST the system STABILITY in the below settings, \n otherwise REMOVE this launchd IMMEDIATELY \n");
    printf("You can remove this by using: ./voltageshift removelaunchd\n ");
    printf("Or manual remove by:\n");
    printf("sudo rm /Library/LaunchDaemons/com.sicreative.VoltageShift.plist\n ");
    printf("sudo rm -R /Library/Application\\ Support/VoltageShift \n");

    printf("--------------------------------------------------------------------------\n");
    printf("CPU             %d %s mv\n",(int)values[0],values[0]>0?"!!!!!":"");
    printf("GPU             %d %s mv\n",(int)values[1],values[1]>0?"!!!!!":"");
    printf("CPU Cache       %d %s mv\n",(int)values[2],values[2]>0?"!!!!!":"");
    printf("System Agency   %d %s mv\n",(int)values[3],values[3]>0?"!!!!!":"");
    printf("Analog IO       %d %s mv\n",(int)values[4],values[4]>0?"!!!!!":"");
    printf("Digital IO      %d %s mv\n",(int)values[5],values[5]>0?"!!!!!":"");
    printf("Long term power     %.03f W\n",values[6]);
    printf("Long term window    %.03f W\n",values[7]);
    printf("Short term power    %.03f W\n",values[8]);
    printf("Short term window   %.03f W\n",values[9]);
    printf("--------------------------------------------------------------------------\n");
    printf("************************************************************************\n");

    printf("Please notice if you cannot boot the system after installing, you need to:\n");
    printf("1. Fully turn off Computer (not reboot):\n");
    printf("2. Boot start by Command-R to recovery mode :\n");
    printf("3. In \"Terminal\" Enable the CSR protection to stop undervoltage running when boot \n");
    printf("4.       csrutil enable    \n");
    printf("5. Reboot and Remove all file above\n");
    printf("--------------------------------------------------------------------------\n");

    
    

    
    
   // output.str("sudo cp ./test.plist /Library/LaunchDaemons ");
    
   //     system(output.str().c_str());
    
}

void *map_physical(uint64_t phys_addr, size_t len)
{
    kern_return_t err;
#if __LP64__
    mach_vm_address_t addr;
    mach_vm_size_t size;
#else
    vm_address_t addr;
    vm_size_t size;
#endif
    size_t dataInLen = sizeof(map_t);
    size_t dataOutLen = sizeof(map_t);
    map_t in, out;
    
    in.addr = phys_addr;
    in.size = len;
    
#ifdef DEBUG
    printf("map_phys: phys %08llx, %08zx\n", phys_addr, len);
#endif
    
#if !defined(__LP64__) && defined(WANT_OLD_API)
    /* Check if OSX 10.5 API is available */
    if (IOConnectCallStructMethod != NULL) {
#endif
        err = IOConnectCallStructMethod(connect, AnVMSRActionMethodPrepareMap, &in, dataInLen, &out, &dataOutLen);
#if !defined(__LP64__) && defined(WANT_OLD_API)
    } else {
        /* Use old API */
        err = IOConnectMethodStructureIStructureO(connect, kPrepareMap, dataInLen, &dataOutLen, &in, &out);
    }
#endif
    
    if (err != KERN_SUCCESS) {
        printf("\nError(kPrepareMap): system 0x%x subsystem 0x%x code 0x%x ",
               err_get_system(err), err_get_sub(err), err_get_code(err));
        
        printf("physical 0x%08llx[0x%x]\n", phys_addr, (unsigned int)len);
        
        switch (err_get_code(err)) {
            case 0x2c2: printf("Invalid argument.\n"); errno = EINVAL; break;
            case 0x2cd: printf("Device not open.\n"); errno = ENOENT; break;
        }
        
        return MAP_FAILED;
    }
    
    err = IOConnectMapMemory(connect, 0, mach_task_self(),
                             &addr, &size, kIOMapAnywhere | kIOMapInhibitCache);
    
    /* Now this is odd; The above connect seems to be unfinished at the
     * time the function returns. So wait a little bit, or the calling
     * program will just segfault. Bummer. Who knows a better solution?
     */
    usleep(1000);
    
    if (err != KERN_SUCCESS) {
        printf("\nError(IOConnectMapMemory): system 0x%x subsystem 0x%x code 0x%x ",
               err_get_system(err), err_get_sub(err), err_get_code(err));
        
        printf("physical 0x%08llx[0x%x]\n", phys_addr, (unsigned int)len);
        
        switch (err_get_code(err)) {
            case 0x2c2: printf("Invalid argument.\n"); errno = EINVAL; break;
            case 0x2cd: printf("Device not open.\n"); errno = ENOENT; break;
        }
        
        return MAP_FAILED;
    }
    
#ifdef DEBUG
    printf("map_phys: virt %08llx, %08llx\n", addr, size);
#endif
    
    return (void *)addr;
}

void unmap_physical(void *virt_addr __attribute__((unused)), size_t len __attribute__((unused)))
{
    // Nut'n Honey
}

int access_direct_memory(uintptr_t addr, uint64_t *value, bool write)
{
    // align to a page boundary
    const uintptr_t page_mask = 0xFFF;
    const size_t len = 8;
    const uintptr_t page_offset = addr & page_mask;
    const uintptr_t map_addr = addr & ~page_mask;
    const size_t map_len = (len + page_offset + page_mask) & ~page_mask;
    
    volatile uint8_t * const map_buf = (uint8_t *) map_physical(map_addr, map_len);
    if (map_buf == NULL)
    {
        printf("Map memory %08lx failed.", addr);
        return -1;
    }
    volatile uint8_t * const buf = map_buf + page_offset;
    
    if (!write) {
        *value = *((uint64_t*)buf);
    } else {
        *((uint64_t*)buf) = *value;
    }
//    unmap_physical(map_addr, map_len);
    
    return 0;
}

int read_msr(uint32_t addr, uint64_t *value)
{
    inout in;
    inout out;
    size_t outsize = sizeof(out);
    int ret;
    
    in.msr = addr;
    in.action = AnVMSRActionMethodRDMSR;
    in.param = 0;
    
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
    ret = IOConnectMethodStructureIStructureO( connect, AnVMSRActionMethodRDMSR,
                                              sizeof(in),            /* structureInputSize */
                                              &outsize,    /* structureOutputSize */
                                              &in,        /* inputStructure */
                                              &out);       /* ouputStructure */
#else
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodRDMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
#endif
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't connect to StructMethod to send commands\n");
        return -1;
    }
    
    *value = out.param;
    return 0;
}

int write_msr(uint32_t addr, uint64_t *value)
{
    inout in;
    inout out;
    size_t outsize = sizeof(out);
    int ret;
    
    in.msr = addr;
    in.action = AnVMSRActionMethodWRMSR;
    in.param = *value;
    
    ret = IOConnectCallStructMethod(connect,
                                    AnVMSRActionMethodWRMSR,
                                    &in,
                                    sizeof(in),
                                    &out,
                                    &outsize
                                    );
    
    if (ret != KERN_SUCCESS)
    {
        printf("Can't connect to StructMethod to send commands\n");
        return -1;
    }
    return 0;
}

static float power_to_seconds(int value, int time_unit) {
    float multiplier = 1 + ((value >> 6) & 0x3) / 4.f;
    int exponent = (value >> 1) & 0x1f;
    return exp2f(exponent) * multiplier / time_unit;
}

static int power_from_seconds(float seconds, int time_unit) {
    if (log2f(seconds * time_unit / 1.75f) >= 0x1f) {
        return 0xfe;
    } else {
        int i;
        float last_diff = 1.f;
        int last_result = 0;
        for (i = 0; i < 4; i++) {
            float multiplier = 1 + (i / 4.f);
            float value = seconds * time_unit / multiplier;
            float exponent = log2f(value);
            int exponent_int = (int) exponent;
            float diff = exponent - exponent_int;
            if (exponent_int < 0x19 && diff > 0.5f) {
                exponent_int++;
                diff = 1.f - diff;
            }
            if (exponent_int < 0x20) {
                if (diff < last_diff) {
                    last_diff = diff;
                    last_result = (i << 6) | (exponent_int << 1);
                }
            }
        }
        return last_result;
    }
}

int access_power_limit(power_limit *pl, bool write)
{
    if (!pl ||
        (write &&
         (pl->short_power <= 0 ||
          pl->long_power <= 0 ||
          pl->short_power < pl->long_power))) {
             printf("invalid power value!\n");
             return -1;
    }
    
    uint64_t msr_limit;
    uint64_t mem_limit;
    uint64_t units;
    if (read_msr(MSR_ADDR_POWER, &msr_limit)) {
        printf("get msr power limit 0x%x failed!\n", MSR_ADDR_POWER);
        return -1;
    }
    if (access_direct_memory(MCHBAR_ADDR_POWER, &mem_limit, false)) {
        printf("get mchbar 0x%x failed!\n", MCHBAR_ADDR_POWER);
        return -1;
    }
    if (read_msr(MSR_ADDR_UNITS, &units)) {
        printf("get units 0x%x failed!\n", MSR_ADDR_UNITS);
        return -1;
    }
    
    if ((msr_limit >> 63) & 0x1) {
        printf("Warning: power limit is locked\n");
    }
    
    int power_unit = (int) (exp2f(units & 0xf) + 0.5f);
    int time_unit = (int) (exp2f((units >> 16) & 0xf) + 0.5f);
    
    if (write) {
        uint64_t max_term = 0x7fff;
        uint64_t masked = msr_limit & 0xffff0000ffff0000;
        
        uint64_t short_term = (uint64_t)(pl->short_power * power_unit);
        short_term = short_term > max_term ? max_term : short_term;
        
        uint64_t long_term = (uint64_t)(pl->long_power * power_unit);
        long_term = long_term > max_term ? max_term : long_term;
        
        uint64_t value = masked | (short_term << 32) | long_term;
        uint64_t time;
        if (pl->short_time > 0) {
            masked = value & 0xff01ffffffffffff;
            time = power_from_seconds(pl->short_time, time_unit);
            printf("short_time = %f, time = 0x%llx\n", pl->short_time, time);
            value = masked | (time << 48);
        }
        if (pl->long_time > 0) {
            masked = value & 0xffffffffff01ffff;
            time = power_from_seconds(pl->long_time, time_unit);
            printf("long_time = %f, time = 0x%llx\n", pl->long_time, time);
            value = masked | (time << 16);
        }
        value |= (pl->short_enabled ? 1L << 47 : 0) | (pl->long_enabled ? 1L << 15 : 0);
        printf("value to write: 0x%llx\n", value);
        if (access_direct_memory(MCHBAR_ADDR_POWER, &value, true)) {
            printf("set mchbar 0x%x with 0x%llx failed!\n", MCHBAR_ADDR_POWER, value);
            return -1;
        }
        if (write_msr(MSR_ADDR_POWER, &value)) {
            printf("set msr 0x%x with 0x%llx failed!\n", MSR_ADDR_POWER, value);
            return -1;
        }
    } else {
        if (msr_limit != mem_limit) {
            printf("Warning: MSR and memory values are not equal\n");
        }
        float short_term = ((msr_limit >> 32) & 0x7fff) / (float)power_unit;
        float long_term = (msr_limit & 0x7fff) / (float)power_unit;
        bool short_term_enabled = !!((msr_limit >> 47) & 1);
        bool long_term_enabled = !!((msr_limit >> 15) & 1);
        float short_term_window = power_to_seconds(msr_limit >> 48,
                                                   time_unit);
        float long_term_window = power_to_seconds(msr_limit >> 16,
                                                  time_unit);
        
        pl->short_enabled = short_term_enabled;
        pl->short_power = short_term;
        pl->short_time = short_term_window;
        pl->long_enabled = long_term_enabled;
        pl->long_power = long_term;
        pl->long_time = long_term_window;
    }
    
    return 0;
}

int set_power_limit(int argc, const char * argv[])
{
    if (argc < 3) {
        usage(argv[0]);
        return(1);
    }
    
    float val;
    power_limit pl;
    access_power_limit(&pl, false);
    
    printf("--------------------------------------------------------------------------\n");
    printf("VoltageShift offset Tool\n");
    printf("--------------------------------------------------------------------------\n");
    printf("Before set power limit:\n");
    access_power_limit(&pl, false);
    printf("Short term power: %.03f W, %.03f s, %s\n",
           pl.short_power, pl.short_time,
           (pl.short_enabled ? "enabled" : "disabled"));
    printf("Long term power: %.03f W, %.03f s, %s\n",
           pl.long_power, pl.long_time,
           (pl.long_enabled ? "enabled" : "disabled"));
    
    if ((val = strtof((char *)argv[2], NULL)) > 0) {
        pl.long_enabled = true;
        pl.long_power = val;
    }
    if (argc >=4) {
        if ((val = strtof((char *)argv[3], NULL)) > 0) {
            pl.long_enabled = true;
            pl.long_time = val;
        } else {
            pl.long_time = 0;
        }
    }
    if (argc >=5) {
        if ((val = strtof((char *)argv[4], NULL)) > 0) {
            pl.short_enabled = true;
            pl.short_power = val;
        }
    }
    if (argc >=6) {
        if ((val = strtof((char *)argv[5], NULL)) > 0) {
            pl.short_enabled = true;
            pl.short_time = val;
        } else {
            pl.short_time = 0;
        }
    }
    
    access_power_limit(&pl, true);
    
    printf("After set power limit:\n");
    access_power_limit(&pl, false);
    printf("Short term power: %.03f W, %.03f s, %s\n",
           pl.short_power, pl.short_time,
           (pl.short_enabled ? "enabled" : "disabled"));
    printf("Long term power: %.03f W, %.03f s, %s\n",
           pl.long_power, pl.long_time,
           (pl.long_enabled ? "enabled" : "disabled"));
    
    printf("--------------------------------------------------------------------------\n");
    
    return(0);
}

void intHandler(int sig)
{
    char  c;
    
       signal(sig, SIG_IGN);
     printf("\n quit? [y/n] ");
    c = getchar();
    if (c == 'y' || c == 'Y'){
        
            unloadkext();
        
        exit(0);
    }
    else
        signal(SIGINT, intHandler);
    getchar(); // Get new line character
}


int main(int argc, const char * argv[])
{
    char * parameter;
    char * msr;
    char * regvalue;
    service = getService();
 
    
    if (argc >= 2)
    {
        parameter = (char *)argv[1];
        
    } else {
        usage(argv[0]);
        
        return(1);
    }
    
    int count = 0;
    while (!service && strncmp(parameter, "loadkext", 8) && strncmp(parameter, "unloadkext", 10) ){
        loadkext();

        service = getService();
        
        count++;
        
        // Try load 10 times, otherwise error return
        if (count > 10)
            return (1);
    }
		
    
	kern_return_t ret;
	//io_connect_t connect = 0;
	ret = IOServiceOpen(service, mach_task_self(), 0, &connect);
	if (ret != KERN_SUCCESS)
    {
        printf("Couldn't open IO Service\n");
    }

    
    


    if (argc >= 3)
    {
        msr = (char *)argv[2];
    }
    
    if (!strncmp(parameter, "info", 4)){
        printf("------------------------------------------------------\n");
        printf("   VoltageShift Info Tool\n");
        printf("------------------------------------------------------\n");
        printf("CPU voltage offset: %dmv\n",readOCMailBox(0));
        printf("GPU voltage offset: %dmv\n",readOCMailBox(1));
        printf("CPU Cache voltage offset: %dmv\n",readOCMailBox(2));
        printf("System Agency offset: %dmv\n",readOCMailBox(3));
        printf("Analogy I/O: %dmv\n",readOCMailBox(4));
        printf("Digital I/O: %dmv\n",readOCMailBox(5));
        power_limit pl;
        access_power_limit(&pl, false);
        printf("Short term power: %.03f W, %.03f s, %s\n",
               pl.short_power, pl.short_time,
               (pl.short_enabled ? "enabled" : "disabled"));
        printf("Long term power: %.03f W, %.03f s, %s\n",
               pl.long_power, pl.long_time,
               (pl.long_enabled ? "enabled" : "disabled"));
        showcpuinfo();
        printf("\n");

        
    }else if (!strncmp(parameter, "mon", 3)){
        printf("------------------------------------------------------\n");
       printf("   VoltageShift Monitor Tool\n");
        printf("------------------------------------------------------\n");
        printf("    Ctl-C to Exit\n\n");
             signal(SIGINT, intHandler);
            printf("   CPU voltage offset: %dmv\n",readOCMailBox(0));
            printf("   GPU voltage offset: %dmv\n",readOCMailBox(1));
            printf("   CPU Cache voltage offset: %dmv\n",readOCMailBox(2));
            printf("   System Agency offset: %dmv\n",readOCMailBox(3));
            printf("   Analogy I/O: %dmv\n",readOCMailBox(4));
            printf("   Digital I/O: %dmv\n\n",readOCMailBox(5));
            
            //   domain : 0 - CPU
            //            1 - GPU
            //            2 - CPU Cache
            //            3 - System Agency
            //            4 - Analogy I/O
            //            5 - Digtal I/O
            
            do{
                
                
                
                if (showcpuinfo() > 0){
                     fflush(stdout);
                    printf("\r");
                     sleep(1);
                    
           
                //    printf("\r");
                 
                    
                   
                  
                   
                    
                  
                    
                    for (int i=0;i<5;i++){
                    
                    sleep(1);
                        loadkext();
                        service = getService();
                    kern_return_t ret;
                    //io_connect_t connect = 0;
                    ret = IOServiceOpen(service, mach_task_self(), 0, &connect);
                    if (ret != KERN_SUCCESS)
                    {
                        printf("Couldn't open IO Service\n");
                       if (i==4)
                           return (1);
                    }else{
                    
                        break;
                    }
                   }

                    
                }
                
                sleep(1);
                
               
                
                
                 fflush(stdout);
               
                 printf("\r");
              // printf("\r");
            }while (true);
        
        }else if (!strncmp(parameter, "--damage", 8)){
           
            if (argc >=2){
                if (!strncmp((char *)argv[2], "offset", 6)){
                    damagemode = true;
                    
             
                    std::vector<std::string> arg;
                    
                
                    arg.push_back(argv[0]);
                    
         
                    
                    
                    for (int i=1; i<argc-1;i++){
                        arg.push_back(argv[i+1]);
            
                    }
                    
           
                    
                    const char **arrayOfCstrings = new const char*[arg.size()];
                    
                    for (int i = 0; i < arg.size(); ++i)
                        arrayOfCstrings[i] = arg[i].c_str();
                    
                  
                
                   
                    
                    setoffset(argc-1,arrayOfCstrings);

                }else if (!strncmp((char *)argv[2], "offsetdaemons", 13)){
                    
                    damagemode = true;
                    
                    
                    std::vector<std::string> arg;
                    
                    
                    arg.push_back(argv[0]);
                    
                    
                    
                    
                    for (int i=1; i<argc-1;i++){
                        arg.push_back(argv[i+1]);
                        
                    }
                    
                    
                    
                    const char **arrayOfCstrings = new const char*[arg.size()];
                    
                    for (int i = 0; i < arg.size(); ++i)
                        arrayOfCstrings[i] = arg[i].c_str();
                    
                    
                    
                    
                    
                    setoffsetdaemons(argc-1,arrayOfCstrings);

                    
                    
                    }else{
                   
                        usage(argv[0]);
                        
                        return(1);
                    
                }
            }
            
        }else if (!strncmp(parameter, "unloadkext", 10)){
            unloadkext();
       
            
        
        }else if (!strncmp(parameter, "loadkext", 8)){
            loadkext();
            return 0;
            
            
        }else if (!strncmp(parameter, "removelaunchd", 13)){
            removeLaunchDaemons();
        }else if (!strncmp(parameter, "buildlaunchd", 12)){
            
          std::vector<float> arg;
            
            
            if (argc >=3 )
                arg.push_back((int)strtol((char *)argv[2],NULL,10));
            if (argc >=4)
                arg.push_back((int)strtol((char *)argv[3],NULL,10));
            if (argc >=5)
                arg.push_back((int)strtol((char *)argv[4],NULL,10));
            if (argc >=6)
                arg.push_back((int)strtol((char *)argv[5],NULL,10));
            if (argc >=7)
                arg.push_back((int)strtol((char *)argv[6],NULL,10));
            if (argc >=8)
                arg.push_back((int)strtol((char *)argv[7],NULL,10));
            if (argc >=9)
                arg.push_back(strtof((char *)argv[8],NULL));
            if (argc >=10)
                arg.push_back(strtof((char *)argv[9],NULL));
            if (argc >=11)
                arg.push_back(strtof((char *)argv[10],NULL));
            if (argc >=12)
                arg.push_back(strtof((char *)argv[11],NULL));
            if (argc >=13){
                writeLaunchDaemons(arg,(int)strtol((char *)argv[12],NULL,10));
            }else{
            
            writeLaunchDaemons(arg);
            }
            
        }else if (!strncmp(parameter, "offsetdaemons",12)){
            setoffsetdaemons(argc,argv);
        }
        else if (!strncmp(parameter, "offset", 6)){
             setoffset(argc,argv);
    }
    else if (!strncmp(parameter, "powerlimit", 10))
    {
        set_power_limit(argc, argv);
    }
    else if (!strncmp(parameter, "read", 4))
    {
        uint32_t addr = (uint32_t)hex2int(msr);
        uint64_t value;
        
        int ret = read_msr(addr, &value);
        if (ret == 0) {
            printf("RDMSR 0x%x returns value 0x%llx\n", addr, value);
        } else {
            printf("RDMSR 0x%x failed!\n", addr);
        }
    } else if (!strncmp(parameter, "write", 5)) {
        if (argc < 4)
        {
            usage(argv[0]);
            return(1);
        }
        
        regvalue = (char *)argv[3];
        uint32_t addr = (uint32_t)hex2int(msr);
        uint64_t value = (uint64_t)hex2int(regvalue);
        
        int ret = write_msr(addr, &value);
        if (ret == 0) {
            read_msr(addr, &value);
            printf("WRMSR 0x%x returns value 0x%llx\n", addr, value);
        }
    } else if (!strncmp(parameter, "rdmem", 5)) {
        uint32_t addr = (uint32_t)hex2int(msr);
        uint64_t value = 0;
        if (access_direct_memory(addr, &value, false) != 0) {
            printf("read direct memory 0x%x failed", addr);
        } else {
            printf("RDMEM 0x%x returns value 0x%llx\n", addr, value);
        }
    } else if (!strncmp(parameter, "wrmem", 5)) {
        if (argc < 4)
        {
            usage(argv[0]);
            return(1);
        }
        
        regvalue = (char *)argv[3];
        
        uint32_t addr = (uint32_t)hex2int(msr);
        uint64_t value = (uint64_t)hex2int(regvalue);
        
        if (access_direct_memory(addr, &value, true) != 0) {
            printf("write direct memory 0x%x with %llx failed", addr, value);
        } else {
            access_direct_memory(addr, &value, false);
            printf("WRMEM 0x%x returns value 0x%llx\n", addr, value);
        }
    } else {
        usage(argv[0]);

        return(1);
    }

 
        if(connect)
        {
            ret = IOServiceClose(connect);
            if (ret != KERN_SUCCESS)
            {
              //  printf("IOServiceClose failed\n");
            }
        }
        
        if(service)
            IOObjectRelease(service);
    
    

        unloadkext();

    

   
    return 0;
}
           
